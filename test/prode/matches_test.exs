defmodule Prode.MatchesTest do
  use Prode.DataCase, async: true

  import Prode.Factory

  alias Prode.Matches

  describe "get_match!/1" do
    test "returns the match for a valid id" do
      match = insert(:match)
      assert Matches.get_match!(match.id).id == match.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn -> Matches.get_match!(Ecto.UUID.generate()) end
    end
  end

  describe "list_matches_for_tournament/1" do
    test "returns matches ordered by kickoff_at" do
      tournament = insert(:tournament)
      now = DateTime.utc_now(:second)
      m2 = insert(:match, tournament: tournament, kickoff_at: DateTime.add(now, 2, :day),
                   prediction_lock_at: DateTime.add(now, 1, :day))
      m1 = insert(:match, tournament: tournament, kickoff_at: DateTime.add(now, 1, :day),
                   prediction_lock_at: DateTime.add(now, 23, :hour))

      [first, second] = Matches.list_matches_for_tournament(tournament.id)
      assert first.id == m1.id
      assert second.id == m2.id
    end

    test "does not return matches from other tournaments" do
      t1 = insert(:tournament)
      t2 = insert(:tournament)
      insert(:match, tournament: t1)
      insert(:match, tournament: t2)

      assert length(Matches.list_matches_for_tournament(t1.id)) == 1
    end
  end

  describe "list_upcoming_matches/0" do
    test "returns only scheduled unlocked matches with future lock time" do
      now = DateTime.utc_now(:second)
      upcoming = insert(:match, status: :scheduled, locked: false,
                         prediction_lock_at: DateTime.add(now, 1, :hour))
      insert(:match, status: :live, locked: false,
             prediction_lock_at: DateTime.add(now, 1, :hour))
      insert(:match, status: :scheduled, locked: true,
             prediction_lock_at: DateTime.add(now, 1, :hour))
      insert(:match, status: :scheduled, locked: false,
             prediction_lock_at: DateTime.add(now, -1, :minute))

      result_ids = Matches.list_upcoming_matches() |> Enum.map(& &1.id)
      assert upcoming.id in result_ids
      assert length(result_ids) == 1
    end
  end

  describe "any_live_matches?/0" do
    test "returns false when no live matches exist" do
      insert(:match, status: :scheduled)
      refute Matches.any_live_matches?()
    end

    test "returns true when a live match exists" do
      insert(:match, status: :live)
      assert Matches.any_live_matches?()
    end
  end

  describe "upsert_match/1" do
    test "inserts a new match" do
      tournament = insert(:tournament)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)
      now = DateTime.utc_now(:second)

      attrs = %{
        api_football_id: 999_001,
        tournament_id: tournament.id,
        home_team_id: home.id,
        away_team_id: away.id,
        kickoff_at: DateTime.add(now, 1, :day),
        prediction_lock_at: DateTime.add(now, 23, :hour),
        status: :scheduled
      }

      assert {:ok, match} = Matches.upsert_match(attrs)
      assert match.api_football_id == 999_001
    end

    test "updates status and scores on conflict" do
      match = insert(:match, api_football_id: 999_002, status: :scheduled)
      now = DateTime.utc_now(:second)

      attrs = %{
        api_football_id: 999_002,
        tournament_id: match.tournament_id,
        home_team_id: match.home_team_id,
        away_team_id: match.away_team_id,
        kickoff_at: match.kickoff_at,
        prediction_lock_at: match.prediction_lock_at,
        status: :finished,
        home_score: 2,
        away_score: 1
      }

      assert {:ok, updated} = Matches.upsert_match(attrs)
      assert updated.status == :finished
      assert updated.home_score == 2
      assert updated.away_score == 1
      # locked flag must not be touched by upsert
      assert updated.locked == match.locked

      # Only one row in DB
      assert Repo.aggregate(Prode.Matches.Match, :count) == 1

      _ = now
    end
  end

  describe "lock_match!/1" do
    test "sets locked to true" do
      match = insert(:match, locked: false)
      locked = Matches.lock_match!(match)
      assert locked.locked == true
    end
  end
end
