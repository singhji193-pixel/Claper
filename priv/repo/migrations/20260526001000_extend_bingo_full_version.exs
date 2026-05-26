defmodule Claper.Repo.Migrations.ExtendBingoFullVersion do
  use Ecto.Migration

  def change do
    alter table(:bingo_players) do
      add :title, :string
      add :company, :string
      add :intro, :text
      add :email, :string
      add :phone, :string
      add :linkedin_url, :string
      add :website_url, :string
      add :share_title, :boolean, null: false, default: false
      add :share_company, :boolean, null: false, default: false
      add :share_intro, :boolean, null: false, default: false
      add :share_email, :boolean, null: false, default: false
      add :share_phone, :boolean, null: false, default: false
      add :share_linkedin_url, :boolean, null: false, default: false
      add :share_website_url, :boolean, null: false, default: false
    end

    create table(:bingo_settings) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :leaderboard_enabled, :boolean, null: false, default: false
      add :forum_enabled, :boolean, null: false, default: true
      add :contact_sharing_enabled, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:bingo_settings, [:event_id], name: :bingo_settings_event_unique)
    create index(:bingo_connections, [:event_id, :bingo_prompt_id])
  end
end
