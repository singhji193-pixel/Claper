defmodule Claper.Repo.Migrations.AddSpeakerLinkedinUrlToAgendaItems do
  use Ecto.Migration

  def change do
    alter table(:agenda_items) do
      add :speaker_linkedin_url, :text
    end
  end
end
