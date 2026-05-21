defmodule Prode.Repo.Migrations.CreateStages do
  use Ecto.Migration

  def change do
    create table(:stages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tournament_id,
          references(:tournaments, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :slug, :string, null: false
      add :type, :string, null: false
      add :points_multiplier, :float, null: false, default: 1.0
      add :order, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:stages, [:tournament_id])
    create unique_index(:stages, [:tournament_id, :slug])
    create constraint(:stages, :valid_type, check: "type IN ('group', 'knockout')")
    create constraint(:stages, :positive_multiplier, check: "points_multiplier > 0")
  end
end
