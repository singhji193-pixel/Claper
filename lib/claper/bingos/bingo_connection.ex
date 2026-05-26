defmodule Claper.Bingos.BingoConnection do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          pair_key: String.t(),
          event_id: integer(),
          bingo_prompt_id: integer(),
          player_id: integer(),
          connected_player_id: integer(),
          event: Claper.Events.Event.t() | nil,
          prompt: Claper.Bingos.BingoPrompt.t() | nil,
          player: Claper.Bingos.BingoPlayer.t() | nil,
          connected_player: Claper.Bingos.BingoPlayer.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "bingo_connections" do
    field :pair_key, :string

    belongs_to :event, Claper.Events.Event
    belongs_to :prompt, Claper.Bingos.BingoPrompt, foreign_key: :bingo_prompt_id
    belongs_to :player, Claper.Bingos.BingoPlayer
    belongs_to :connected_player, Claper.Bingos.BingoPlayer

    timestamps()
  end

  @doc false
  def changeset(connection, attrs \\ %{}) do
    connection
    |> cast(attrs, [
      :event_id,
      :bingo_prompt_id,
      :player_id,
      :connected_player_id,
      :pair_key
    ])
    |> validate_required([
      :event_id,
      :bingo_prompt_id,
      :player_id,
      :connected_player_id,
      :pair_key
    ])
    |> assoc_constraint(:event)
    |> assoc_constraint(:prompt)
    |> assoc_constraint(:player)
    |> assoc_constraint(:connected_player)
    |> unique_constraint(:player_id, name: :bingo_connections_prompt_player_unique)
    |> unique_constraint(:pair_key, name: :bingo_connections_prompt_pair_unique)
  end
end
