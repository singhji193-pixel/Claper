defmodule Claper.HiEvents.EventTicket do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hi_events_tickets" do
    field :external_attendee_id, :string
    field :external_ticket_id, :string
    field :external_ticket_type_id, :string
    field :ticket_name, :string
    field :attendee_email, :string
    field :attendee_first_name, :string
    field :attendee_last_name, :string
    field :attendee_name, :string
    field :status, :string, default: "active"
    field :checked_in_at, :utc_datetime
    field :raw_payload, :map, default: %{}

    belongs_to :event, Claper.Events.Event
    belongs_to :integration, Claper.HiEvents.Integration
    belongs_to :order, Claper.HiEvents.Order, foreign_key: :hi_events_order_id

    timestamps()
  end

  @doc false
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :event_id,
      :integration_id,
      :hi_events_order_id,
      :external_attendee_id,
      :external_ticket_id,
      :external_ticket_type_id,
      :ticket_name,
      :attendee_email,
      :attendee_first_name,
      :attendee_last_name,
      :attendee_name,
      :status,
      :checked_in_at,
      :raw_payload
    ])
    |> validate_required([:event_id, :integration_id, :status, :raw_payload])
    |> require_attendee_identity()
    |> update_change(:attendee_email, &normalize_email/1)
    |> validate_format(:attendee_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:external_attendee_id, name: :hi_events_tickets_external_attendee_unique)
    |> unique_constraint(:external_ticket_id, name: :hi_events_tickets_external_ticket_unique)
  end

  defp require_attendee_identity(changeset) do
    attendee_id = get_field(changeset, :external_attendee_id)
    ticket_id = get_field(changeset, :external_ticket_id)
    email = get_field(changeset, :attendee_email)

    if present?(attendee_id) || present?(ticket_id) || present?(email) do
      changeset
    else
      add_error(changeset, :external_attendee_id, "or ticket/email is required")
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalize_email(email), do: email
end
