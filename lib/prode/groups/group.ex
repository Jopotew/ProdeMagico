defmodule Prode.Groups.Group do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Accounts.User
  alias Prode.Groups.Membership
  alias Prode.Tournaments.Tournament

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "groups" do
    field :name, :string
    field :description, :string
    field :invite_code, :string
    field :max_members, :integer, default: 50

    belongs_to :owner, User
    belongs_to :tournament, Tournament
    has_many :memberships, Membership
    has_many :members, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description, :invite_code, :max_members, :owner_id, :tournament_id])
    |> validate_required([:name, :invite_code, :owner_id, :tournament_id])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:invite_code, is: 6)
    |> validate_format(:invite_code, ~r/^[A-Z0-9]{6}$/)
    |> validate_number(:max_members, greater_than: 0, less_than_or_equal_to: 500)
    |> unique_constraint(:invite_code)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:tournament_id)
  end
end
