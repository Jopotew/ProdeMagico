defmodule Prode.Predictions.Prediction do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Accounts.User
  alias Prode.Matches.Match

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "predictions" do
    field :home_score, :integer
    field :away_score, :integer
    field :points_awarded, :integer
    field :calculated_at, :utc_datetime

    belongs_to :user, User
    belongs_to :match, Match

    timestamps(type: :utc_datetime)
  end

  def changeset(prediction, attrs, match \\ nil) do
    prediction
    |> cast(attrs, [:home_score, :away_score, :user_id, :match_id])
    |> validate_required([:home_score, :away_score, :user_id, :match_id])
    |> validate_number(:home_score, greater_than_or_equal_to: 0)
    |> validate_number(:away_score, greater_than_or_equal_to: 0)
    |> validate_not_locked(match)
    |> unique_constraint([:user_id, :match_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:match_id)
  end

  defp validate_not_locked(changeset, nil), do: changeset

  defp validate_not_locked(changeset, match) do
    if match.locked or DateTime.after?(DateTime.utc_now(), match.prediction_lock_at) do
      add_error(changeset, :match_id, "predictions are locked for this match")
    else
      changeset
    end
  end
end
