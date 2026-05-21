defmodule Prode.Repo.Migrations.AddNotificationFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :phone_number, :string
      add :whatsapp_opted_in, :boolean, default: false, null: false
      add :whatsapp_verification_code, :string
      add :whatsapp_verification_sent_at, :utc_datetime
    end
  end
end
