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

        emit_prediction_telemetry(result, match.tournament_id)
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

  @doc "Returns a map of match_id => prediction for a user across a list of match IDs."
  def list_predictions_map_for_matches(_user_id, []), do: %{}

  def list_predictions_map_for_matches(user_id, match_ids) when is_list(match_ids) do
    from(p in Prediction,
      where: p.user_id == ^user_id and p.match_id in ^match_ids
    )
    |> Repo.all()
    |> Map.new(&{&1.match_id, &1})
  end

  @doc """
  Returns the top N most-predicted scores for a match, each with a :pct field.
  Returns [] if fewer than 5 total predictions exist (avoids anchoring bias).
  """
  def popular_predictions_for_match(match_id, limit \\ 2) do
    total = Repo.one(from p in Prediction, where: p.match_id == ^match_id, select: count(p.id)) || 0

    if total < 5 do
      []
    else
      from(p in Prediction,
        where: p.match_id == ^match_id and not is_nil(p.home_score),
        group_by: [p.home_score, p.away_score],
        select: %{home_score: p.home_score, away_score: p.away_score, count: count(p.id)},
        order_by: [desc: count(p.id)],
        limit: ^limit
      )
      |> Repo.all()
      |> Enum.map(fn row -> Map.put(row, :pct, round(row.count * 100 / total)) end)
    end
  end

  @doc """
  Returns a map of bonus predictions for a user in a tournament.
  Keys are `{:group_winner, group_letter}` for group winner predictions
  and `:top_scorer` for the top scorer prediction.
  """
  def list_bonus_predictions_map(user_id, tournament_id) do
    alias Prode.Predictions.BonusPrediction

    from(bp in BonusPrediction,
      where: bp.user_id == ^user_id and bp.tournament_id == ^tournament_id
    )
    |> Repo.all()
    |> Map.new(fn bp ->
      key =
        case bp.kind do
          :group_winner -> {:group_winner, bp.payload["group"]}
          :top_scorer -> :top_scorer
        end

      {key, bp}
    end)
  end

  @doc "Submits or replaces a bonus prediction. Validates lock time against the tournament."
  def submit_bonus_prediction(attrs) do
    alias Prode.Predictions.BonusPrediction
    alias Prode.Tournaments

    tournament = Tournaments.get_tournament!(attrs.tournament_id)
    changeset = BonusPrediction.changeset(%BonusPrediction{}, attrs, tournament)

    conflict_target =
      case attrs.kind do
        :top_scorer ->
          {:unsafe_fragment, "(user_id, tournament_id, kind) WHERE kind = 'top_scorer'"}

        :group_winner ->
          {:unsafe_fragment, "(user_id, tournament_id, kind, (payload->>'group'))"}
      end

    Repo.insert(changeset,
      on_conflict: {:replace, [:payload, :updated_at]},
      conflict_target: conflict_target,
      returning: true
    )
  end

  defp emit_prediction_telemetry({:ok, _}, tournament_id) do
    :telemetry.execute([:prode, :prediction, :submitted], %{count: 1}, %{
      tournament_id: tournament_id
    })
  end

  defp emit_prediction_telemetry({:error, _}, _tournament_id), do: nil
end
