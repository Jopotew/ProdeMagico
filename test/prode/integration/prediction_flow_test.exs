defmodule Prode.Integration.PredictionFlowTest do
  @moduledoc """
  End-to-end test: user joins group → predicts match → match finishes →
  PointsCalculator runs → leaderboard reflects correct points.
  """

  use Prode.DataCase, async: false
  use Oban.Testing, repo: Prode.Repo

  import Prode.Factory

  alias Prode.{Groups, Predictions}
  alias Prode.Workers.PointsCalculator

  setup do
    tournament = insert(:tournament)
    stage = insert(:stage, tournament: tournament, type: :group, points_multiplier: 1.0)

    match =
      insert(:match,
        tournament: tournament,
        stage: stage,
        status: :scheduled,
        locked: false,
        prediction_lock_at: DateTime.add(DateTime.utc_now(:second), 1, :hour),
        home_score: nil,
        away_score: nil
      )

    owner = insert(:user)
    {:ok, group} = Groups.create_group(owner, %{name: "Test Group", tournament_id: tournament.id})

    predictor = insert(:user)
    {:ok, _group} = Groups.join_by_invite_code(predictor, group.invite_code)

    %{match: match, group: group, predictor: predictor, owner: owner}
  end

  test "predicting, finishing a match, and running points calculator updates leaderboard",
       %{match: match, group: group, predictor: predictor} do
    # Submit a prediction (exact score: 2-1)
    assert {:ok, prediction} =
             Predictions.upsert_prediction(%{
               user_id: predictor.id,
               match_id: match.id,
               home_score: 2,
               away_score: 1
             })

    assert prediction.home_score == 2
    assert prediction.points_awarded == nil

    # Simulate match finishing with the exact predicted score
    match
    |> Ecto.Changeset.change(%{status: :finished, home_score: 2, away_score: 1})
    |> Prode.Repo.update!()

    # Run PointsCalculator (Oban inline mode in test)
    assert :ok = perform_job(PointsCalculator, %{"match_id" => match.id})

    # Prediction should now have points
    updated = Prode.Repo.get!(Prode.Predictions.Prediction, prediction.id)
    assert updated.points_awarded == 5
    assert updated.calculated_at != nil

    # Leaderboard should show the predictor with 5 points
    [row | _] = Groups.leaderboard_for_group(group.id)
    assert row.total == 5
  end

  test "points calculator is idempotent — re-running does not double points",
       %{match: match, predictor: predictor} do
    insert(:prediction,
      user: predictor,
      match: match,
      home_score: 1,
      away_score: 0,
      points_awarded: nil,
      calculated_at: nil
    )

    match
    |> Ecto.Changeset.change(%{status: :finished, home_score: 1, away_score: 0})
    |> Prode.Repo.update!()

    assert :ok = perform_job(PointsCalculator, %{"match_id" => match.id})
    assert :ok = perform_job(PointsCalculator, %{"match_id" => match.id})

    predictions = Prode.Repo.all(
      from p in Prode.Predictions.Prediction,
        where: p.match_id == ^match.id and p.user_id == ^predictor.id
    )

    assert length(predictions) == 1
    assert hd(predictions).points_awarded == 5
  end

  test "points calculator snoozes when match is not yet finished", %{match: match} do
    assert {:snooze, 60} = perform_job(PointsCalculator, %{"match_id" => match.id})
  end

  test "wrong outcome prediction scores 0 points", %{match: match, predictor: predictor} do
    insert(:prediction,
      user: predictor,
      match: match,
      home_score: 2,
      away_score: 1,
      points_awarded: nil,
      calculated_at: nil
    )

    match
    |> Ecto.Changeset.change(%{status: :finished, home_score: 0, away_score: 3})
    |> Prode.Repo.update!()

    assert :ok = perform_job(PointsCalculator, %{"match_id" => match.id})

    [pred] = Prode.Repo.all(
      from p in Prode.Predictions.Prediction, where: p.match_id == ^match.id
    )

    assert pred.points_awarded == 0
  end

  import Ecto.Query
end
