defmodule Claper.Repo.Migrations.AddKindToPosts do
  use Ecto.Migration

  def up do
    alter table(:posts) do
      add :kind, :string, null: false, default: "message"
    end

    execute("UPDATE posts SET kind = 'question' WHERE body LIKE '%?%'")
    create index(:posts, [:event_id, :kind, :id])

    create constraint(:posts, :posts_kind_check, check: "kind IN ('question', 'message')")
  end

  def down do
    drop constraint(:posts, :posts_kind_check)
    drop index(:posts, [:event_id, :kind, :id])

    alter table(:posts) do
      remove :kind
    end
  end
end
