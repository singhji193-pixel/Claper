defmodule Claper.BingosFixtures do
  @moduledoc """
  This module defines test helpers for creating Bingo entities.
  """

  import Claper.EventsFixtures

  require Claper.UtilFixture

  def bingo_prompt_fixture(attrs \\ %{}, preload \\ []) do
    assoc = %{event: attrs[:event] || event_fixture()}

    {:ok, prompt} =
      attrs
      |> Enum.into(%{
        event_id: assoc.event.id,
        prompt: "Find someone who has launched a product"
      })
      |> Claper.Bingos.create_prompt()

    Claper.UtilFixture.merge_preload(prompt, preload, assoc)
  end

  def bingo_player_fixture(attrs \\ %{}, preload \\ []) do
    assoc = %{event: attrs[:event] || event_fixture()}

    attendee_identifier =
      attrs[:attendee_identifier] || "attendee-#{System.unique_integer([:positive])}"

    {:ok, player} =
      attrs
      |> Enum.into(%{
        event_id: assoc.event.id,
        attendee_identifier: attendee_identifier,
        name: "Avery Singh"
      })
      |> Claper.Bingos.create_player()

    Claper.UtilFixture.merge_preload(player, preload, assoc)
  end

  def bingo_settings_fixture(attrs \\ %{}) do
    event = attrs[:event] || event_fixture()

    {:ok, settings} =
      event.id
      |> Claper.Bingos.get_or_create_settings()
      |> Claper.Bingos.update_settings(Map.delete(attrs, :event))

    settings
  end
end
