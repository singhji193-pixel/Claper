defmodule Claper.HiEvents.Integration do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hi_events_integrations" do
    field :external_event_id, :string
    field :webhook_secret, :string
    field :enabled, :boolean, default: true
    field :last_event_key, :string
    field :last_event_type, :string
    field :last_received_at, :utc_datetime
    field :last_error, :string
    field :remote_webhook_id, :string
    field :last_reconciled_at, :utc_datetime
    field :last_reconcile_status, :string

    belongs_to :event, Claper.Events.Event

    timestamps()
  end

  @doc false
  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [:event_id, :external_event_id, :webhook_secret, :enabled])
    |> validate_required([:event_id, :external_event_id, :webhook_secret, :enabled])
    |> update_change(:external_event_id, &trim_string/1)
    |> update_change(:webhook_secret, &trim_string/1)
    |> validate_length(:external_event_id, min: 1, max: 160)
    |> validate_format(:external_event_id, ~r/^[A-Za-z0-9_-]+$/)
    |> validate_length(:webhook_secret, min: 24, max: 160)
    |> unique_constraint(:event_id, name: :hi_events_integrations_event_unique)
    |> unique_constraint(:external_event_id, name: :hi_events_integrations_external_event_unique)
  end

  def status_changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :last_event_key,
      :last_event_type,
      :last_received_at,
      :last_error,
      :last_reconciled_at,
      :last_reconcile_status
    ])
  end

  def connection_changeset(integration, attrs) do
    integration
    |> cast(attrs, [:remote_webhook_id, :webhook_secret])
    |> validate_required([:remote_webhook_id, :webhook_secret])
    |> validate_length(:webhook_secret, min: 24, max: 160)
  end

  defp trim_string(nil), do: nil
  defp trim_string(value), do: String.trim(value)
end
