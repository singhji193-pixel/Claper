defmodule Claper.Bingos.BingoPrompt do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          prompt: String.t(),
          position: integer(),
          event_id: integer(),
          event: Claper.Events.Event.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "bingo_prompts" do
    field :prompt, :string
    field :position, :integer, default: 0

    belongs_to :event, Claper.Events.Event

    timestamps()
  end

  @doc false
  def changeset(prompt, attrs \\ %{}) do
    prompt
    |> cast(attrs, [:event_id, :prompt, :position])
    |> validate_required([:event_id, :prompt, :position])
    |> validate_length(:prompt, min: 3, max: 500)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> assoc_constraint(:event)
  end
end
