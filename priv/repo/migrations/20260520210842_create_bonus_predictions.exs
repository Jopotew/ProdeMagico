defmodule Prode.Repo.Migrations.CreateBonusPredictions do
  use Ecto.Migration

  def change do
    create table(:bonus_predictions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :points_awarded, :integer
      add :calculated_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :tournament_id, references(:tournaments, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bonus_predictions, [:user_id, :tournament_id, :kind, "(payload->>'group')"],
             name: :bonus_predictions_user_tournament_kind_group_index
           )

    create index(:bonus_predictions, [:tournament_id])
  end
end
