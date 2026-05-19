defmodule Claper.AgendasFixtures do
  @moduledoc """
  This module defines test helpers for creating agenda entities.
  """

  import Claper.EventsFixtures

  require Claper.UtilFixture

  def agenda_item_fixture(attrs \\ %{}, preload \\ []) do
    assoc = %{event: attrs[:event] || event_fixture()}

    {:ok, agenda_item} =
      attrs
      |> Enum.into(%{
        event_id: assoc.event.id,
        starts_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        title: "Opening session",
        description: "Welcome and setup",
        speaker_name: "CoreOrbit Team",
        duration_minutes: 30
      })
      |> Claper.Agendas.create_agenda_item()

    Claper.UtilFixture.merge_preload(agenda_item, preload, assoc)
  end
end
