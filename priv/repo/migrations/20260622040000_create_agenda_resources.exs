defmodule Claper.Repo.Migrations.CreateAgendaResources do
  use Ecto.Migration

  def change do
    create table(:agenda_resources) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :agenda_item_id, references(:agenda_items, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :kind, :string, null: false, default: "link"
      add :url, :text, null: false
      add :position, :integer, null: false, default: 0
      add :published, :boolean, null: false, default: false

      timestamps()
    end

    create index(:agenda_resources, [:event_id])
    create index(:agenda_resources, [:agenda_item_id, :position, :id])

    create constraint(:agenda_resources, :agenda_resources_kind_check,
             check: "kind IN ('pdf', 'slides', 'recording', 'link')"
           )
  end
end
