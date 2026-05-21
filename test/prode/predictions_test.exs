defmodule Prode.PredictionsTest do
  use Prode.DataCase, async: true

  import Prode.Factory

  alias Prode.Predictions

  defp future_match(attrs \\ []) do
    now = DateTime.utc_now(:second)

    insert(:match,
      Keyword.merge(
        [
          status: :scheduled,
          locked: false,
          kickoff_at: DateTime.add(now, 1, :day),
          prediction_lock_at: DateTime.add(now, 23, :hour)
        ],
        attrs
      )
    )
  end

  describe "upsert_prediction/1" do
    test "creates a prediction for an open match" do
      user = insert(:user)
      match = future_match()

      attrs = %{user_id: user.id, match_id: match.id, home_score: 2, away_score: 1}
      assert {:ok, pred} = Predictions.upsert_prediction(attrs)
      assert pred.home_score == 2
      assert pred.away_score == 1
    end

    test "updates an existing prediction before lock" do
      user = insert(:user)
      match = future_match()

      attrs = %{user_id: user.id, match_id: match.id, home_score: 1, away_score: 0}
      {:ok, _} = Predictions.upsert_prediction(attrs)

      updated_attrs = %{attrs | home_score: 3, away_score: 2}
      assert {:ok, pred} = Predictions.upsert_prediction(updated_attrs)
      assert pred.home_score == 3
      assert pred.away_score == 2

      # Still only one row
      assert Repo.aggregate(Prode.Predictions.Prediction, :count) == 1
    end

    test "rejects prediction when match is already locked" do
      user = insert(:user)
      match = future_match(locked: true)

      attrs = %{user_id: user.id, match_id: match.id, home_score: 1, away_score: 0}
      assert {:error, changeset} = Predictions.upsert_prediction(attrs)
      assert "predictions are locked for this match" in errors_on(changeset).match_id
    end

    test "rejects prediction when prediction_lock_at has passed" do
      user = insert(:user)
      now = DateTime.utc_now(:second)

      match =
        insert(:match,
          status: :live,
          locked: false,
          kickoff_at: DateTime.add(now, -1, :hour),
          prediction_lock_at: DateTime.add(now, -15, :minute)
        )

      attrs = %{user_id: user.id, match_id: match.id, home_score: 0, away_score: 0}
      assert {:error, changeset} = Predictions.upsert_prediction(attrs)
      assert "predictions are locked for this match" in errors_on(changeset).match_id
    end

    test "rejects negative scores" do
      user = insert(:user)
      match = future_match()

      attrs = %{user_id: user.id, match_id: match.id, home_score: -1, away_score: 0}
      assert {:error, changeset} = Predictions.upsert_prediction(attrs)
      assert changeset.errors[:home_score]
    end
  end

  describe "get_prediction/2" do
    test "returns the prediction when it exists" do
      pred = insert(:prediction)
      result = Predictions.get_prediction(pred.user_id, pred.match_id)
      assert result.id == pred.id
    end

    test "returns nil when no prediction exists" do
      assert nil == Predictions.get_prediction(Ecto.UUID.generate(), Ecto.UUID.generate())
    end
  end

  describe "list_predictions_for_user/1" do
    test "returns all predictions for a user with match preloaded" do
      user = insert(:user)
      insert(:prediction, user: user)
      insert(:prediction, user: user)
      insert(:prediction)

      preds = Predictions.list_predictions_for_user(user.id)
      assert length(preds) == 2
      assert Enum.all?(preds, fn p -> p.user_id == user.id end)
      assert Enum.all?(preds, fn p -> not is_nil(p.match) end)
    end
  end
end
