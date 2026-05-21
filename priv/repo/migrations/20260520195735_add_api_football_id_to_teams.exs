defmodule Prode.Repo.Migrations.AddApiFootballIdToTeams do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :api_football_id, :integer
    end

    create unique_index(:teams, [:tournament_id, :api_football_id],
             where: "api_football_id IS NOT NULL"
           )
  end
end
