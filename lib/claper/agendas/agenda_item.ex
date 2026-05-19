defmodule Claper.Agendas.AgendaItem do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          starts_at: NaiveDateTime.t(),
          title: String.t(),
          description: String.t() | nil,
          speaker_name: String.t() | nil,
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
      :duration_minutes,
      :position
    ])
    |> validate_required([:event_id, :starts_at, :title, :position])
    |> validate_length(:title, max: 255)
    |> validate_length(:speaker_name, max: 255)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 1440)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> assoc_constraint(:event)
  end
end
