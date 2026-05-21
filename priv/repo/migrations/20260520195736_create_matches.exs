defmodule Prode.Repo.Migrations.CreateMatches do
  use Ecto.Migration

  def change do
    create table(:matches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tournament_id,
          references(:tournaments, type: :binary_id, on_delete: :delete_all),
          null: false

      add :stage_id,
          references(:stages, type: :binary_id, on_delete: :nilify_all)

      add :home_team_id,
          references(:teams, type: :binary_id, on_delete: :restrict),
          null: false

      add :away_team_id,
          references(:teams, type: :binary_id, on_delete: :restrict),
          null: false

      add :api_football_id, :integer, null: false
      add :round, :string
      add :kickoff_at, :utc_datetime, null: false
      add :prediction_lock_at, :utc_datetime, null: false
      add :locked, :boolean, null: false, default: false
      add :status, :string, null: false, default: "scheduled"
      add :home_score, :integer
      add :away_score, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:matches, [:api_football_id])
    create index(:matches, [:tournament_id])
    create index(:matches, [:stage_id])
    create index(:matches, [:kickoff_at])
    create index(:matches, [:status])

    create constraint(:matches, :valid_status,
             check: "status IN ('scheduled', 'live', 'finished', 'postponed', 'cancelled')"
           )
  end
end
