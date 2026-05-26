defmodule Prode.Workers.BonusPointsCalculatorTest do
  use Prode.DataCase, async: true

  import Prode.Factory

  alias Prode.Predictions.BonusPrediction
  alias Prode.Repo
  alias Prode.Workers.BonusPointsCalculator

  defp run_job(tournament_id, kind, payload) do
    BonusPointsCalculator.perform(%Oban.Job{
      args: %{"tournament_id" => tournament_id, "kind" => kind, "payload" => payload}
    })
  end

  describe "perform/1 — top_scorer bonus" do
    test "awards 10 pts when predicted player is in actual top scorers" do
      tournament = insert(:tournament)
      user = insert(:user)

      bp =
        insert(:bonus_prediction,
          user: user,
          tournament: tournament,
          kind: :top_scorer,
          payload: %{"player_id" => 42}
        )

      assert :ok = run_job(tournament.id, "top_scorer", %{"actual_top_scorer_ids" => [42, 99]})

      updated = Repo.get!(BonusPrediction, bp.id)
      assert updated.points_awarded == 10
      assert updated.calculated_at != nil
    end

    test "awards 0 pts when predicted player is not in actual top scorers" do
      tournament = insert(:tournament)
      user = insert(:user)

      bp =
        insert(:bonus_prediction,
          user: user,
          tournament: tournament,
          kind: :top_scorer,
          payload: %{"player_id" => 42}
        )

      assert :ok = run_job(tournament.id, "top_scorer", %{"actual_top_scorer_ids" => [99, 100]})

      assert Repo.get!(BonusPrediction, bp.id).points_awarded == 0
    end

    test "is idempotent — skips already-calculated predictions" do
      tournament = insert(:tournament)
      user = insert(:user)

      bp =
        insert(:bonus_prediction,
          user: user,
          tournament: tournament,
          kind: :top_scorer,
          payload: %{"player_id" => 42},
          points_awarded: 10,
          calculated_at: DateTime.utc_now(:second)
        )

      assert :ok = run_job(tournament.id, "top_scorer", %{"actual_top_scorer_ids" => [99]})

      assert Repo.get!(BonusPrediction, bp.id).points_awarded == 10
    end
  end

  describe "perform/1 — group_winner bonus" do
    test "awards 10 pts when predicted team matches actual winner" do
      tournament = insert(:tournament)
      user = insert(:user)

      bp =
        insert(:bonus_prediction,
          user: user,
          tournament: tournament,
          kind: :group_winner,
          payload: %{"team_id" => "abc-123"}
        )

      assert :ok =
               run_job(tournament.id, "group_winner", %{
                 "group" => "A",
                 "actual_winner_id" => "abc-123"
               })

      assert Repo.get!(BonusPrediction, bp.id).points_awarded == 10
    end

    test "awards 0 pts when predicted team does not match actual winner" do
      tournament = insert(:tournament)
      user = insert(:user)

      bp =
        insert(:bonus_prediction,
          user: user,
          tournament: tournament,
          kind: :group_winner,
          payload: %{"team_id" => "abc-123"}
        )

      assert :ok =
               run_job(tournament.id, "group_winner", %{
                 "group" => "A",
                 "actual_winner_id" => "different-team"
               })

      assert Repo.get!(BonusPrediction, bp.id).points_awarded == 0
    end
  end

  describe "perform/1 — PubSub broadcast" do
    test "broadcasts :leaderboard_updated to groups of affected users" do
      tournament = insert(:tournament)
      user = insert(:user)
      group = insert(:group, tournament: tournament, owner: user)
      insert(:membership, group: group, user: user, role: :admin)

      insert(:bonus_prediction,
        user: user,
        tournament: tournament,
        kind: :top_scorer,
        payload: %{"player_id" => 7}
      )

      Phoenix.PubSub.subscribe(Prode.PubSub, "group:#{group.id}")

      assert :ok = run_job(tournament.id, "top_scorer", %{"actual_top_scorer_ids" => [7]})

      expected_id = group.id
      assert_receive {:leaderboard_updated, ^expected_id}, 500
    end
  end
end
