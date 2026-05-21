defmodule Prode.Tournaments.Stage do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Tournaments.Tournament

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stages" do
    field :name, :string
    field :slug, :string
    field :type, Ecto.Enum, values: [:group, :knockout]
    field :points_multiplier, :float, default: 1.0
    field :order, :integer

    belongs_to :tournament, Tournament

    timestamps(type: :utc_datetime)
  end

  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:name, :slug, :type, :points_multiplier, :order, :tournament_id])
    |> validate_required([:name, :slug, :type, :points_multiplier, :order, :tournament_id])
    |> validate_inclusion(:type, [:group, :knockout])
    |> validate_number(:points_multiplier, greater_than: 0)
    |> unique_constraint([:tournament_id, :slug])
    |> foreign_key_constraint(:tournament_id)
  end
end
