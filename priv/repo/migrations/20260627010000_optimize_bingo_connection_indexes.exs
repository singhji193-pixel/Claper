defmodule Claper.Repo.Migrations.OptimizeBingoConnectionIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:bingo_connections, [:event_id, :player_id],
                           name: :bingo_connections_event_player_index
                         )

    create_if_not_exists index(:bingo_connections, [:event_id, :connected_player_id],
                           name: :bingo_connections_event_connected_player_index
                         )
  end
end
