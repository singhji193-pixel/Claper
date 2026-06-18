defmodule Claper.Repo.Migrations.CreateEventAppAttendeeAuth do
  use Ecto.Migration

  def change do
    create table(:event_app_attendees) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :hi_events_ticket_id, references(:hi_events_tickets, on_delete: :nilify_all)
      add :email, :string, null: false
      add :name, :string
      add :first_name, :string
      add :last_name, :string
      add :ticket_name, :string
      add :verified_at, :utc_datetime
      add :last_seen_at, :utc_datetime

      timestamps()
    end

    create unique_index(:event_app_attendees, [:event_id, :email],
             name: :event_app_attendees_event_email_unique
           )

    create index(:event_app_attendees, [:event_id])
    create index(:event_app_attendees, [:hi_events_ticket_id])

    create table(:event_app_otp_challenges) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :code_hash, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts_count, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 5
      add :expires_at, :utc_datetime, null: false
      add :sent_at, :utc_datetime
      add :consumed_at, :utc_datetime
      add :delivery_status, :string, null: false, default: "pending"
      add :delivery_error, :text
      add :request_ip, :string
      add :user_agent, :text

      timestamps()
    end

    create index(:event_app_otp_challenges, [:event_id, :email, :inserted_at])
    create index(:event_app_otp_challenges, [:event_id, :email, :status, :expires_at])

    create table(:event_app_sessions) do
      add :event_id, references(:events, on_delete: :delete_all), null: false

      add :event_app_attendee_id, references(:event_app_attendees, on_delete: :delete_all),
        null: false

      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime
      add :user_agent, :text

      timestamps()
    end

    create unique_index(:event_app_sessions, [:token_hash],
             name: :event_app_sessions_token_hash_unique
           )

    create index(:event_app_sessions, [:event_id, :expires_at])
    create index(:event_app_sessions, [:event_app_attendee_id])
  end
end
