defmodule Prode.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Leaderboard query: fetch all predictions for a user
    create index(:predictions, [:user_id])
    # PointsCalculator: WHERE calculated_at IS NULL
    create index(:predictions, [:calculated_at])
    # BonusPointsCalculator: WHERE calculated_at IS NULL
    create index(:bonus_predictions, [:calculated_at])
    create index(:bonus_predictions, [:user_id])
    # MatchLocker startup: upcoming unlocked matches
    create index(:matches, [:prediction_lock_at])
    create index(:matches, [:locked])
  end
end
