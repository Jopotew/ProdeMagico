defmodule Prode.Repo.Migrations.CreatePredictions do
  use Ecto.Migration

  def change do
    create table(:predictions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :match_id,
          references(:matches, type: :binary_id, on_delete: :delete_all),
          null: false

      add :home_score, :integer, null: false
      add :away_score, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:predictions, [:user_id, :match_id])
    create index(:predictions, [:match_id])
    create constraint(:predictions, :non_negative_scores,
             check: "home_score >= 0 AND away_score >= 0"
           )
  end
end
