defmodule Prode.Repo.Migrations.AddGoogleFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_uid, :string, null: true
      add :display_name, :string, null: true
      add :avatar_url, :string, null: true
    end

    create unique_index(:users, [:google_uid], where: "google_uid IS NOT NULL")
  end
end
