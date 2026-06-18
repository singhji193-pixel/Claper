defmodule Claper.HiEvents.SyncEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hi_events_sync_events" do
    field :external_event_id, :string
    field :external_event_type, :string
    field :external_event_key, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "received"
    field :error, :string
    field :received_at, :utc_datetime
    field :processed_at, :utc_datetime

    belongs_to :event, Claper.Events.Event
    belongs_to :integration, Claper.HiEvents.Integration

    timestamps()
  end

  @doc false
  def changeset(sync_event, attrs) do
    sync_event
    |> cast(attrs, [
      :event_id,
      :integration_id,
      :external_event_id,
      :external_event_type,
      :external_event_key,
      :payload,
      :status,
      :error,
      :received_at,
      :processed_at
    ])
    |> validate_required([
      :event_id,
      :integration_id,
      :external_event_id,
      :external_event_type,
      :external_event_key,
      :payload,
      :status,
      :received_at
    ])
    |> validate_inclusion(:status, ["received", "processed", "failed"])
    |> unique_constraint(:external_event_key, name: :hi_events_sync_events_delivery_unique)
  end

  def status_changeset(sync_event, attrs) do
    sync_event
    |> cast(attrs, [:status, :error, :processed_at])
    |> validate_inclusion(:status, ["received", "processed", "failed"])
  end
end
