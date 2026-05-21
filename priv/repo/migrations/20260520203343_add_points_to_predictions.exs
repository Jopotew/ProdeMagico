defmodule Prode.Repo.Migrations.AddPointsToPredictions do
  use Ecto.Migration

  def change do
    alter table(:predictions) do
      add :points_awarded, :integer
      add :calculated_at, :utc_datetime
    end
  end
end
