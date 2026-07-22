defmodule Claper.Repo.Migrations.AddSpeakerImageUrlToAgendaItems do
  use Ecto.Migration

  def change do
    alter table(:agenda_items) do
      add :speaker_image_url, :string
    end
  end
end
