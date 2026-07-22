defmodule Claper.Agendas.AgendaItem do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          starts_at: NaiveDateTime.t(),
          title: String.t(),
          description: String.t() | nil,
          speaker_name: String.t() | nil,
          speaker_title: String.t() | nil,
          speaker_company: String.t() | nil,
          speaker_image_url: String.t() | nil,
          location_name: String.t() | nil,
          track_name: String.t() | nil,
          session_type: String.t() | nil,
          duration_minutes: integer() | nil,
          position: integer(),
          event_id: integer(),
          event: Claper.Events.Event.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "agenda_items" do
    field :starts_at, :naive_datetime
    field :title, :string
    field :description, :string
    field :speaker_name, :string
    field :speaker_title, :string
    field :speaker_company, :string
    field :speaker_image_url, :string
    field :location_name, :string
    field :track_name, :string
    field :session_type, :string
    field :duration_minutes, :integer
    field :position, :integer, default: 0

    belongs_to :event, Claper.Events.Event

    timestamps()
  end

  @doc false
  def changeset(agenda_item, attrs \\ %{}) do
    agenda_item
    |> cast(attrs, [
      :event_id,
      :starts_at,
      :title,
      :description,
      :speaker_name,
      :speaker_title,
      :speaker_company,
      :speaker_image_url,
      :location_name,
      :track_name,
      :session_type,
      :duration_minutes,
      :position
    ])
    |> validate_required([:event_id, :starts_at, :title, :position])
    |> validate_length(:title, max: 255)
    |> validate_length(:speaker_name, max: 255)
    |> validate_length(:speaker_title, max: 255)
    |> validate_length(:speaker_company, max: 255)
    |> validate_length(:speaker_image_url, max: 255)
    |> validate_format(:speaker_image_url, ~r{^https?://}, message: "must be an http(s) URL")
    |> validate_length(:location_name, max: 255)
    |> validate_length(:track_name, max: 120)
    |> validate_length(:session_type, max: 120)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 1440)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> assoc_constraint(:event)
  end
end
