defmodule Prode.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, default: "member", null: false
      add :joined_at, :utc_datetime, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :group_id, references(:groups, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:user_id, :group_id])
    create index(:memberships, [:group_id])
  end
end
