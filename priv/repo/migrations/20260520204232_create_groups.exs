defmodule Prode.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :invite_code, :string, null: false, size: 6
      add :max_members, :integer, default: 50, null: false
      add :owner_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :tournament_id, references(:tournaments, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:groups, [:invite_code])
    create index(:groups, [:owner_id])
    create index(:groups, [:tournament_id])
  end
end
