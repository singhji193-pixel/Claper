defmodule Claper.Repo.Migrations.WidenAgendaSpeakerImageUrl do
  use Ecto.Migration

  def change do
    alter table(:agenda_items) do
      modify :speaker_image_url, :text, from: :string
    end
  end
end
