defmodule Claper.Repo.Migrations.CreateAgendaItems do
  use Ecto.Migration

  def change do
    create table(:agenda_items) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :starts_at, :naive_datetime, null: false
      add :title, :string, null: false
      add :description, :text
      add :speaker_name, :string
      add :duration_minutes, :integer
      add :position, :integer, null: false, default: 0

      timestamps()
    end

    create index(:agenda_items, [:event_id, :position])
    create index(:agenda_items, [:event_id, :starts_at])
  end
end
