defmodule Claper.EventApp.Attendee do
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_app_attendees" do
    field :email, :string
    field :name, :string
    field :first_name, :string
    field :last_name, :string
    field :ticket_name, :string
    field :verified_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    belongs_to :event, Claper.Events.Event
    belongs_to :hi_events_ticket, Claper.HiEvents.EventTicket

    timestamps()
  end

  @doc false
  def changeset(attendee, attrs) do
    attendee
    |> cast(attrs, [
      :event_id,
      :hi_events_ticket_id,
      :email,
      :name,
      :first_name,
      :last_name,
      :ticket_name,
      :verified_at,
      :last_seen_at
    ])
    |> validate_required([:event_id, :email, :verified_at])
    |> update_change(:email, &normalize_email/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:email, name: :event_app_attendees_event_email_unique)
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_email(email), do: email
end
