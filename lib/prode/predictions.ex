defmodule Prode.Predictions do
  @moduledoc """
  Context for prediction management with three-layer lock enforcement.
  """

  import Ecto.Query, warn: false

  alias Prode.Matches.Match
  alias Prode.Predictions.Prediction
  alias Prode.Repo

  @doc """
  Creates or updates a prediction for a user on a match.

  Enforces the 15-minute lock window at three levels:
  1. Changeset validation (lock flag + time check)
  2. `SELECT … FOR UPDATE` row lock inside a transaction

  Returns `{:ok, prediction}`, `{:error, changeset}`, or `{:error, :match_locked}`.
  """
  def upsert_prediction(attrs) do
    Repo.transact(fn ->
      match =
        Repo.one!(from m in Match, where: m.id == ^attrs.match_id, lock: "FOR UPDATE")

      changeset = Prediction.changeset(%Prediction{}, attrs, match)

      if changeset.valid? do
        result =
          Repo.insert(changeset,
            on_conflict: {:replace, [:home_score, :away_score, :updated_at]},
            conflict_target: [:user_id, :match_id],
            returning: true
          )

        case result do
          {:ok, _} ->
            :telemetry.execute([:prode, :prediction, :submitted], %{count: 1}, %{
              tournament_id: match.tournament_id
            })

          {:error, _} ->
            nil
        end

        result
      else
        :telemetry.execute([:prode, :prediction, :rejected], %{count: 1}, %{reason: :validation})
        {:error, changeset}
      end
    end)
  end

  @doc "Returns the prediction for a given user and match, or nil."
  def get_prediction(user_id, match_id) do
    Repo.get_by(Prediction, user_id: user_id, match_id: match_id)
  end

  @doc "Returns all predictions for a user."
  def list_predictions_for_user(user_id) do
    Repo.all(from p in Prediction, where: p.user_id == ^user_id, preload: [:match])
  end

  @doc "Returns user IDs of all users who made a prediction for the given match."
  def user_ids_with_predictions_for_match(match_id) do
    Repo.all(from p in Prediction, where: p.match_id == ^match_id, select: p.user_id, distinct: true)
  end

  @doc "Submits or replaces a bonus prediction. Validates lock time against the tournament."
  def submit_bonus_prediction(attrs) do
    alias Prode.Predictions.BonusPrediction
    alias Prode.Tournaments

    tournament = Tournaments.get_tournament!(attrs.tournament_id)
    changeset = BonusPrediction.changeset(%BonusPrediction{}, attrs, tournament)

    Repo.insert(changeset,
      on_conflict: {:replace, [:payload, :updated_at]},
      conflict_target: [:user_id, :tournament_id, :kind],
      returning: true
    )
  end
end
