defmodule Prode.Predictions.BonusPrediction do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Accounts.User
  alias Prode.Tournaments.Tournament

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds [:top_scorer, :group_winner]

  schema "bonus_predictions" do
    field :kind, Ecto.Enum, values: @kinds
    field :payload, :map, default: %{}
    field :points_awarded, :integer
    field :calculated_at, :utc_datetime

    belongs_to :user, User
    belongs_to :tournament, Tournament

    timestamps(type: :utc_datetime)
  end

  def changeset(bonus_prediction, attrs, tournament \\ nil) do
    bonus_prediction
    |> cast(attrs, [:kind, :payload, :user_id, :tournament_id])
    |> validate_required([:kind, :payload, :user_id, :tournament_id])
    |> validate_payload()
    |> validate_not_locked(tournament)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tournament_id)
  end

  defp validate_payload(changeset) do
    kind = get_field(changeset, :kind)
    payload = get_field(changeset, :payload)

    case {kind, payload} do
      {:top_scorer, %{"player_id" => id}} when is_integer(id) ->
        changeset

      {:group_winner, %{"group" => g, "team_id" => id}} when is_binary(g) and is_integer(id) ->
        changeset

      {nil, _} ->
        changeset

      _ ->
        add_error(changeset, :payload, "invalid payload for kind #{kind}")
    end
  end

  defp validate_not_locked(changeset, nil), do: changeset

  defp validate_not_locked(changeset, %Tournament{bonus_predictions_lock_at: nil}), do: changeset

  defp validate_not_locked(changeset, %Tournament{bonus_predictions_lock_at: lock_at}) do
    if DateTime.after?(DateTime.utc_now(), lock_at) do
      add_error(changeset, :tournament_id, "bonus predictions are locked for this tournament")
    else
      changeset
    end
  end
end
