defmodule Claper.Repo.Migrations.AddEventAppInteractionIdentity do
  use Ecto.Migration

  def change do
    alter table(:event_app_attendees) do
      add :interaction_key, :uuid, null: false, default: fragment("gen_random_uuid()")
    end

    create unique_index(:event_app_attendees, [:interaction_key],
             name: :event_app_attendees_interaction_key_unique
           )
  end
end
