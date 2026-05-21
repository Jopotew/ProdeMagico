defmodule Prode.Repo.Migrations.AddBonusLockToTournaments do
  use Ecto.Migration

  def change do
    alter table(:tournaments) do
      add :bonus_predictions_lock_at, :utc_datetime
    end
  end
end
