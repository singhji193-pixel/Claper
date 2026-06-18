defmodule Claper.EventApp.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_app_sessions" do
    field :token_hash, :string
    field :expires_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :user_agent, :string

    belongs_to :event, Claper.Events.Event
    belongs_to :attendee, Claper.EventApp.Attendee, foreign_key: :event_app_attendee_id

    timestamps()
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :event_id,
      :event_app_attendee_id,
      :token_hash,
      :expires_at,
      :last_seen_at,
      :user_agent
    ])
    |> validate_required([:event_id, :event_app_attendee_id, :token_hash, :expires_at])
    |> unique_constraint(:token_hash, name: :event_app_sessions_token_hash_unique)
  end

  def touch_changeset(session, attrs) do
    session
    |> cast(attrs, [:last_seen_at])
    |> validate_required([:last_seen_at])
  end
end
