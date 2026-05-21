defmodule Prode.Repo.Migrations.CreateTournaments do
  use Ecto.Migration

  def change do
    create table(:tournaments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :season, :integer, null: false
      add :status, :string, null: false, default: "upcoming"
      add :starts_on, :date
      add :ends_on, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tournaments, [:season])

    create constraint(:tournaments, :valid_status,
             check: "status IN ('upcoming', 'active', 'finished')"
           )
  end
end
