defmodule Prode.Workers.FixtureSyncWorkerTest do
  use Prode.DataCase, async: false
  use Oban.Testing, repo: Prode.Repo

  import Mox
  import Prode.Factory

  alias Prode.Matches
  alias Prode.Workers.FixtureSyncWorker

  setup :verify_on_exit!

  @fixture %{
    "fixture" => %{
      "id" => 1_149_393,
      "date" => "2026-06-11T19:00:00+00:00",
      "status" => %{"short" => "NS", "long" => "Not Started", "elapsed" => nil}
    },
    "league" => %{"id" => 1, "season" => 2026, "round" => "Group Stage - 1"},
    "teams" => %{
      "home" => %{"id" => 16, "name" => "Mexico"},
      "away" => %{"id" => 33, "name" => "Canada"}
    },
    "goals" => %{"home" => nil, "away" => nil}
  }

  setup do
    tournament = insert(:tournament, season: 2026)
    insert(:stage, tournament: tournament, slug: "group_a", name: "Group A")
    {:ok, tournament: tournament}
  end

  test "creates match and teams from fixture data" do
    expect(Prode.External.MockSportsDataClient, :list_fixtures, fn _ ->
      {:ok, [@fixture]}
    end)

    assert :ok = perform_job(FixtureSyncWorker, %{})

    assert [match] = Matches.list_matches_for_tournament(
      Prode.Repo.get_by!(Prode.Tournaments.Tournament, season: 2026).id
    )
    assert match.api_football_id == 1_149_393
    assert match.status == :scheduled
    assert match.prediction_lock_at == ~U[2026-06-11 18:45:00Z]
  end

  test "updates an existing match on re-sync" do
    expect(Prode.External.MockSportsDataClient, :list_fixtures, fn _ ->
      {:ok, [@fixture]}
    end)

    assert :ok = perform_job(FixtureSyncWorker, %{})

    finished_fixture = put_in(@fixture, ["fixture", "status", "short"], "FT")
    finished_fixture = put_in(finished_fixture, ["goals", "home"], 2)
    finished_fixture = put_in(finished_fixture, ["goals", "away"], 1)

    expect(Prode.External.MockSportsDataClient, :list_fixtures, fn _ ->
      {:ok, [finished_fixture]}
    end)

    assert :ok = perform_job(FixtureSyncWorker, %{})

    tournament = Prode.Repo.get_by!(Prode.Tournaments.Tournament, season: 2026)
    [match] = Matches.list_matches_for_tournament(tournament.id)
    assert match.status == :finished
    assert match.home_score == 2
    assert match.away_score == 1
  end

  test "returns error when tournament not found" do
    Prode.Repo.delete_all(Prode.Tournaments.Tournament)

    assert {:error, :tournament_not_found} = perform_job(FixtureSyncWorker, %{})
  end

  test "returns error when API call fails" do
    expect(Prode.External.MockSportsDataClient, :list_fixtures, fn _ ->
      {:error, :timeout}
    end)

    assert {:error, :timeout} = perform_job(FixtureSyncWorker, %{})
  end
end
