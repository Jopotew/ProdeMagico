defmodule Prode.Tournaments.Tournament do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Tournaments.{Stage, Team}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tournaments" do
    field :name, :string
    field :season, :integer
    field :status, Ecto.Enum, values: [:upcoming, :active, :finished], default: :upcoming
    field :starts_on, :date
    field :ends_on, :date
    field :bonus_predictions_lock_at, :utc_datetime

    has_many :stages, Stage
    has_many :teams, Team

    timestamps(type: :utc_datetime)
  end

  def changeset(tournament, attrs) do
    tournament
    |> cast(attrs, [:name, :season, :status, :starts_on, :ends_on, :bonus_predictions_lock_at])
    |> validate_required([:name, :season])
    |> validate_inclusion(:status, [:upcoming, :active, :finished])
    |> unique_constraint(:season)
  end
end
