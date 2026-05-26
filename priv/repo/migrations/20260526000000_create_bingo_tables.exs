defmodule Claper.Repo.Migrations.CreateBingoTables do
  use Ecto.Migration

  def change do
    create table(:bingo_prompts) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :prompt, :text, null: false
      add :position, :integer, null: false, default: 0

      timestamps()
    end

    create index(:bingo_prompts, [:event_id, :position])

    create table(:bingo_players) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :attendee_identifier, :string, null: false
      add :name, :string, null: false
      add :code, :string, null: false

      timestamps()
    end

    create unique_index(:bingo_players, [:event_id, :attendee_identifier],
             name: :bingo_players_event_attendee_unique
           )

    create unique_index(:bingo_players, [:event_id, :code],
             name: :bingo_players_event_code_unique
           )

    create table(:bingo_connections) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :bingo_prompt_id, references(:bingo_prompts, on_delete: :delete_all), null: false
      add :player_id, references(:bingo_players, on_delete: :delete_all), null: false
      add :connected_player_id, references(:bingo_players, on_delete: :delete_all), null: false
      add :pair_key, :string, null: false

      timestamps()
    end

    create index(:bingo_connections, [:event_id])

    create unique_index(:bingo_connections, [:bingo_prompt_id, :player_id],
             name: :bingo_connections_prompt_player_unique
           )

    create unique_index(:bingo_connections, [:bingo_prompt_id, :pair_key],
             name: :bingo_connections_prompt_pair_unique
           )
  end
end
