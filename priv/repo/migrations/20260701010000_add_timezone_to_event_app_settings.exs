defmodule Claper.Repo.Migrations.AddTimezoneToEventAppSettings do
  use Ecto.Migration

  def change do
    alter table(:event_app_settings) do
      add :timezone, :string, null: false, default: "America/Vancouver"
    end
  end
end
