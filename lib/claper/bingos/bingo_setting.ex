defmodule Claper.Bingos.BingoSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          leaderboard_enabled: boolean(),
          forum_enabled: boolean(),
          contact_sharing_enabled: boolean(),
          event_id: integer(),
          event: Claper.Events.Event.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "bingo_settings" do
    field :leaderboard_enabled, :boolean, default: false
    field :forum_enabled, :boolean, default: true
    field :contact_sharing_enabled, :boolean, default: true

    belongs_to :event, Claper.Events.Event

    timestamps()
  end

  @doc false
  def changeset(settings, attrs \\ %{}) do
    settings
    |> cast(attrs, [:event_id, :leaderboard_enabled, :forum_enabled, :contact_sharing_enabled])
    |> validate_required([
      :event_id,
      :leaderboard_enabled,
      :forum_enabled,
      :contact_sharing_enabled
    ])
    |> assoc_constraint(:event)
    |> unique_constraint(:event_id, name: :bingo_settings_event_unique)
  end
end
