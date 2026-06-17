defmodule Claper.Repo.Migrations.CreateEventAppSettings do
  use Ecto.Migration

  def change do
    create table(:event_app_settings) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :enabled, :boolean, null: false, default: true
      add :install_prompt_enabled, :boolean, null: false, default: true
      add :ticket_enabled, :boolean, null: false, default: false
      add :people_enabled, :boolean, null: false, default: false
      add :chat_enabled, :boolean, null: false, default: false
      add :sponsors_enabled, :boolean, null: false, default: false
      add :primary_color, :string, null: false, default: "#f15a24"
      add :accent_color, :string, null: false, default: "#365a91"

      add :home_tagline, :string,
        null: false,
        default: "Your event companion for schedule, networking, and live moments."

      timestamps()
    end

    create unique_index(:event_app_settings, [:event_id], name: :event_app_settings_event_unique)
  end
end
