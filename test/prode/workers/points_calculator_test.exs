defmodule Prode.Workers.PointsCalculatorTest do
  use Prode.DataCase, async: true

  import Prode.Factory

  alias Prode.{Predictions.Prediction, Repo}
  alias Prode.Workers.PointsCalculator

  defp run_job(match_id) do
    PointsCalculator.perform(%Oban.Job{args: %{"match_id" => match_id}})
  end

  describe "perform/1 — finished match" do
    test "awards correct points and sets calculated_at" do
      tournament = insert(:tournament)
      stage = insert(:stage, tournament: tournament, type: :group, points_multiplier: 1.0)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      match =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          status: :finished,
          home_score: 2,
          away_score: 1,
          locked: true,
          stage: stage
        )

      user = insert(:user)
      # Exact score prediction — 5 pts
      pred = insert(:prediction, user: user, match: match, home_score: 2, away_score: 1)

      assert :ok = run_job(match.id)

      updated = Repo.get!(Prediction, pred.id)
      assert updated.points_awarded == 5
      assert updated.calculated_at != nil
    end

    test "correct outcome but wrong score — 3 pts" do
      tournament = insert(:tournament)
      stage = insert(:stage, tournament: tournament, type: :group, points_multiplier: 1.0)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      match =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          status: :finished,
          home_score: 2,
          away_score: 0,
          stage: stage
        )

      user = insert(:user)
      pred = insert(:prediction, user: user, match: match, home_score: 1, away_score: 0)

      assert :ok = run_job(match.id)

      assert Repo.get!(Prediction, pred.id).points_awarded == 3
    end

    test "wrong outcome — 0 pts" do
      tournament = insert(:tournament)
      stage = insert(:stage, tournament: tournament, type: :group, points_multiplier: 1.0)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      match =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          status: :finished,
          home_score: 2,
          away_score: 0,
          stage: stage
        )

      user = insert(:user)
      pred = insert(:prediction, user: user, match: match, home_score: 0, away_score: 1)

      assert :ok = run_job(match.id)

      assert Repo.get!(Prediction, pred.id).points_awarded == 0
    end

    test "is idempotent — skips already-calculated predictions" do
      tournament = insert(:tournament)
      stage = insert(:stage, tournament: tournament, type: :group, points_multiplier: 1.0)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      match =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          status: :finished,
          home_score: 1,
          away_score: 1,
          stage: stage
        )

      user = insert(:user)

      pred =
        insert(:prediction,
          user: user,
          match: match,
          home_score: 1,
          away_score: 1,
          points_awarded: 5,
          calculated_at: DateTime.utc_now(:second)
        )

      assert :ok = run_job(match.id)

      # Points should remain unchanged (not recalculated)
      assert Repo.get!(Prediction, pred.id).points_awarded == 5
    end

    test "snoozes if match is not yet finished" do
      tournament = insert(:tournament)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      match =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          status: :live
        )

      assert {:snooze, 60} = run_job(match.id)
    end

    test "broadcasts :leaderboard_updated to all affected groups" do
      tournament = insert(:tournament)
      stage = insert(:stage, tournament: tournament, type: :group, points_multiplier: 1.0)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      match =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          status: :finished,
          home_score: 1,
          away_score: 0,
          stage: stage
        )

      user = insert(:user)
      group = insert(:group, tournament: tournament, owner: user)
      insert(:membership, group: group, user: user, role: :admin)
      insert(:prediction, user: user, match: match, home_score: 1, away_score: 0)

      Phoenix.PubSub.subscribe(Prode.PubSub, "group:#{group.id}")

      assert :ok = run_job(match.id)

      expected_id = group.id
      assert_receive {:leaderboard_updated, ^expected_id}, 500
    end
  end
end
