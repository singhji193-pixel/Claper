defmodule Claper.Repo.Migrations.CreateHiEventsSyncTables do
  use Ecto.Migration

  def change do
    create table(:hi_events_integrations) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :external_event_id, :string, null: false
      add :webhook_secret, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :last_event_key, :string
      add :last_event_type, :string
      add :last_received_at, :utc_datetime
      add :last_error, :text

      timestamps()
    end

    create unique_index(:hi_events_integrations, [:event_id],
             name: :hi_events_integrations_event_unique
           )

    create unique_index(:hi_events_integrations, [:external_event_id],
             name: :hi_events_integrations_external_event_unique
           )

    create table(:hi_events_sync_events) do
      add :event_id, references(:events, on_delete: :delete_all), null: false

      add :integration_id, references(:hi_events_integrations, on_delete: :delete_all),
        null: false

      add :external_event_id, :string, null: false
      add :external_event_type, :string, null: false
      add :external_event_key, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "received"
      add :error, :text
      add :received_at, :utc_datetime, null: false
      add :processed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:hi_events_sync_events, [:integration_id, :external_event_key],
             name: :hi_events_sync_events_delivery_unique
           )

    create index(:hi_events_sync_events, [:event_id, :received_at])

    create table(:hi_events_orders) do
      add :event_id, references(:events, on_delete: :delete_all), null: false

      add :integration_id, references(:hi_events_integrations, on_delete: :delete_all),
        null: false

      add :external_order_id, :string, null: false
      add :status, :string, null: false, default: "active"
      add :buyer_name, :string
      add :buyer_email, :string
      add :total_cents, :integer
      add :currency, :string
      add :raw_payload, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:hi_events_orders, [:integration_id, :external_order_id],
             name: :hi_events_orders_external_order_unique
           )

    create index(:hi_events_orders, [:event_id])

    create table(:hi_events_tickets) do
      add :event_id, references(:events, on_delete: :delete_all), null: false

      add :integration_id, references(:hi_events_integrations, on_delete: :delete_all),
        null: false

      add :hi_events_order_id, references(:hi_events_orders, on_delete: :nilify_all)
      add :external_attendee_id, :string
      add :external_ticket_id, :string
      add :external_ticket_type_id, :string
      add :ticket_name, :string
      add :attendee_email, :string
      add :attendee_first_name, :string
      add :attendee_last_name, :string
      add :attendee_name, :string
      add :status, :string, null: false, default: "active"
      add :checked_in_at, :utc_datetime
      add :raw_payload, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:hi_events_tickets, [:integration_id, :external_attendee_id],
             name: :hi_events_tickets_external_attendee_unique
           )

    create unique_index(:hi_events_tickets, [:integration_id, :external_ticket_id],
             where: "external_ticket_id IS NOT NULL",
             name: :hi_events_tickets_external_ticket_unique
           )

    create index(:hi_events_tickets, [:event_id])
    create index(:hi_events_tickets, [:event_id, :attendee_email])
  end
end
