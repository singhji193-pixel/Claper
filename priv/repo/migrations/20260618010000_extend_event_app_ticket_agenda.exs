defmodule Claper.Repo.Migrations.ExtendEventAppTicketAgenda do
  use Ecto.Migration

  def change do
    alter table(:agenda_items) do
      add :location_name, :string
      add :track_name, :string
      add :session_type, :string
      add :speaker_title, :string
      add :speaker_company, :string
    end

    create index(:agenda_items, [:event_id, :track_name])
    create index(:agenda_items, [:event_id, :location_name])

    create table(:event_app_agenda_bookmarks) do
      add :event_id, references(:events, on_delete: :delete_all), null: false

      add :event_app_attendee_id, references(:event_app_attendees, on_delete: :delete_all),
        null: false

      add :agenda_item_id, references(:agenda_items, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:event_app_agenda_bookmarks, [:event_app_attendee_id, :agenda_item_id],
             name: :event_app_agenda_bookmarks_attendee_item_unique
           )

    create index(:event_app_agenda_bookmarks, [:event_id, :event_app_attendee_id])
    create index(:event_app_agenda_bookmarks, [:agenda_item_id])
  end
end
