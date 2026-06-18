defmodule Claper.Repo.Migrations.FixHiEventsTicketAttendeeIndex do
  use Ecto.Migration

  def change do
    drop_if_exists index(:hi_events_tickets, [:integration_id, :external_attendee_id],
                     name: :hi_events_tickets_external_attendee_unique
                   )

    create unique_index(:hi_events_tickets, [:integration_id, :external_attendee_id],
             name: :hi_events_tickets_external_attendee_unique
           )
  end
end
