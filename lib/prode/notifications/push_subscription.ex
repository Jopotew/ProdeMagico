defmodule Prode.Notifications.PushSubscription do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:endpoint, :p256dh, :auth, :user_id])
    |> validate_required([:endpoint, :p256dh, :auth, :user_id])
    |> unique_constraint(:endpoint)
    |> foreign_key_constraint(:user_id)
  end
end
