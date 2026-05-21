defmodule Prode.Tournaments.Team do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Tournaments.Tournament

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "teams" do
    field :api_football_id, :integer
    field :name, :string
    field :code, :string
    field :logo_url, :string
    field :group, :string

    belongs_to :tournament, Tournament

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:api_football_id, :name, :code, :logo_url, :group, :tournament_id])
    |> validate_required([:name, :code, :tournament_id])
    |> validate_length(:code, min: 2, max: 3)
    |> unique_constraint([:tournament_id, :code])
    |> foreign_key_constraint(:tournament_id)
  end
end
