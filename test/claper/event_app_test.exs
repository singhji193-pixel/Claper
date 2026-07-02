defmodule Claper.EventAppTest do
  use Claper.DataCase

  import Claper.{AgendasFixtures, BingosFixtures, EventsFixtures}

  alias Claper.EventApp

  describe "bootstrap_event/2" do
    test "returns public event app state without creating settings" do
      event = event_fixture()
      agenda_item_fixture(%{event: event, title: "Opening session"})
      bingo_prompt_fixture(%{event: event, prompt: "Find another founder"})

      assert {:ok, bootstrap} = EventApp.bootstrap_event(event.code, "attendee-token")

      assert bootstrap.event.code == event.code
      assert bootstrap.event.name == event.name
      assert bootstrap.settings.enabled
      assert bootstrap.settings.theme.primary_color == "#C9A84C"
      assert bootstrap.features.agenda.available
      assert bootstrap.features.agenda.count == 1
      assert bootstrap.features.bingo.available
      assert bootstrap.features.bingo.count == 1
      assert bootstrap.attendee.identifier_present
      refute EventApp.get_settings(event.id)
    end

    test "returns not found for missing or expired events" do
      assert {:error, :not_found} = EventApp.bootstrap_event("missing-code")
    end
  end

  describe "settings" do
    test "creates event app settings with defaults" do
      event = event_fixture()

      setting = EventApp.get_or_create_settings(event.id)

      assert setting.enabled
      assert setting.install_prompt_enabled
      refute setting.people_enabled
      refute setting.live_interactions_enabled
      refute setting.qa_enabled
      refute setting.resources_enabled
      assert setting.primary_color == "#C9A84C"
      assert setting.accent_color == "#8B6218"
      assert setting.timezone == "America/Vancouver"
    end

    test "rejects an invalid timezone" do
      event = event_fixture()
      setting = EventApp.get_or_create_settings(event.id)

      assert {:error, changeset} = EventApp.update_settings(setting, %{timezone: "Not/AZone"})
      assert "is not a valid timezone" in errors_on(changeset).timezone
    end

    test "accepts a valid timezone update" do
      event = event_fixture()
      setting = EventApp.get_or_create_settings(event.id)

      assert {:ok, updated} = EventApp.update_settings(setting, %{timezone: "America/Toronto"})
      assert updated.timezone == "America/Toronto"
    end

    test "event_timezone/1 returns the configured or default timezone" do
      event = event_fixture()

      assert EventApp.event_timezone(event.id) == "America/Vancouver"

      setting = EventApp.get_or_create_settings(event.id)
      {:ok, _updated} = EventApp.update_settings(setting, %{timezone: "America/Toronto"})

      assert EventApp.event_timezone(event.id) == "America/Toronto"
    end

    test "publishes disabled-by-default Live feature settings" do
      event = event_fixture()

      assert {:ok, bootstrap} = EventApp.bootstrap_event(event.code)
      refute bootstrap.settings.live_interactions_enabled
      refute bootstrap.settings.qa_enabled
      refute bootstrap.settings.resources_enabled
      assert bootstrap.features.live.type == nil
      refute bootstrap.features.live.active
    end
  end
end
