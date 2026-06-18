defmodule Claper.EventApp.AgendaBookmark do
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_app_agenda_bookmarks" do
    belongs_to :event, Claper.Events.Event
    belongs_to :attendee, Claper.EventApp.Attendee, foreign_key: :event_app_attendee_id
    belongs_to :agenda_item, Claper.Agendas.AgendaItem

    timestamps()
  end

  @doc false
  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [:event_id, :event_app_attendee_id, :agenda_item_id])
    |> validate_required([:event_id, :event_app_attendee_id, :agenda_item_id])
    |> unique_constraint(:agenda_item_id, name: :event_app_agenda_bookmarks_attendee_item_unique)
    |> assoc_constraint(:event)
    |> assoc_constraint(:attendee)
    |> assoc_constraint(:agenda_item)
  end
end
