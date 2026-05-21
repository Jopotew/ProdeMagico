defmodule Prode.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tournament_id,
          references(:tournaments, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :code, :string, null: false
      add :logo_url, :string
      add :group, :string

      timestamps(type: :utc_datetime)
    end

    create index(:teams, [:tournament_id])
    create unique_index(:teams, [:tournament_id, :code])
    create index(:teams, [:tournament_id, :group])
  end
end
