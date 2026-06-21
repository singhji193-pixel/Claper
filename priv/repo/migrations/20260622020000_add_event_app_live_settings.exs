defmodule Claper.Repo.Migrations.AddEventAppLiveSettings do
  use Ecto.Migration

  def change do
    alter table(:event_app_settings) do
      add :live_interactions_enabled, :boolean, null: false, default: false
      add :qa_enabled, :boolean, null: false, default: false
      add :resources_enabled, :boolean, null: false, default: false
    end
  end
end
