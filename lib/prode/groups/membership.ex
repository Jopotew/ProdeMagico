defmodule Prode.Groups.Membership do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Accounts.User
  alias Prode.Groups.Group

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    field :role, Ecto.Enum, values: [:member, :admin], default: :member
    field :joined_at, :utc_datetime

    belongs_to :user, User
    belongs_to :group, Group

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :joined_at, :user_id, :group_id])
    |> validate_required([:joined_at, :user_id, :group_id])
    |> unique_constraint([:user_id, :group_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:group_id)
  end
end
