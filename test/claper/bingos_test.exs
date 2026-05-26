defmodule Claper.BingosTest do
  use Claper.DataCase

  alias Claper.Bingos
  alias Claper.Bingos.{BingoPlayer, BingoPrompt, BingoSetting}
  alias Claper.Repo

  import Claper.{BingosFixtures, EventsFixtures}

  describe "prompts" do
    test "create_prompt/1 appends prompts to the event" do
      event = event_fixture()

      assert {:ok, first} = Bingos.create_prompt(%{event_id: event.id, prompt: "First prompt"})
      assert {:ok, second} = Bingos.create_prompt(%{event_id: event.id, prompt: "Second prompt"})

      assert first.position == 0
      assert second.position == 1
    end

    test "create_prompt/1 rejects invalid attributes" do
      assert {:error, changeset} = Bingos.create_prompt(%{prompt: ""})

      assert "can't be blank" in errors_on(changeset).event_id
      assert "can't be blank" in errors_on(changeset).prompt
    end

    test "list_prompts/1 only returns prompts for the requested event in order" do
      event = event_fixture()
      other_event = event_fixture()

      first = bingo_prompt_fixture(%{event: event, prompt: "First"})
      second = bingo_prompt_fixture(%{event: event, prompt: "Second"})
      _other = bingo_prompt_fixture(%{event: other_event, prompt: "Other"})

      assert [first.id, second.id] == event.id |> Bingos.list_prompts() |> Enum.map(& &1.id)
    end

    test "get_prompt_for_event!/2 scopes lookup to the event" do
      event = event_fixture()
      other_event = event_fixture()
      prompt = bingo_prompt_fixture(%{event: event})

      assert Bingos.get_prompt_for_event!(event.id, prompt.id).id == prompt.id

      assert_raise Ecto.NoResultsError, fn ->
        Bingos.get_prompt_for_event!(other_event.id, prompt.id)
      end
    end

    test "update, delete, and move prompts" do
      event = event_fixture()
      first = bingo_prompt_fixture(%{event: event, prompt: "First"})
      second = bingo_prompt_fixture(%{event: event, prompt: "Second"})
      third = bingo_prompt_fixture(%{event: event, prompt: "Third"})

      assert {:ok, updated} = Bingos.update_prompt(first, %{prompt: "Updated first"})
      assert updated.prompt == "Updated first"

      assert {:ok, _items} = Bingos.move_prompt(event.id, third.id, :up)

      assert [first.id, third.id, second.id] ==
               event.id |> Bingos.list_prompts() |> Enum.map(& &1.id)

      assert {:ok, deleted} = Bingos.delete_prompt(third)
      assert deleted.id == third.id

      assert [{first.id, 0}, {second.id, 1}] ==
               event.id |> Bingos.list_prompts() |> Enum.map(&{&1.id, &1.position})
    end

    test "event deletion cascades Bingo prompts and players" do
      event = event_fixture()
      prompt = bingo_prompt_fixture(%{event: event})
      player = bingo_player_fixture(%{event: event})

      assert {:ok, _event} = Claper.Events.delete_event(event)
      refute Repo.get(BingoPrompt, prompt.id)
      refute Repo.get(BingoPlayer, player.id)
    end
  end

  describe "players and connections" do
    test "ensure_player/3 creates and updates one player for an attendee session" do
      event = event_fixture()

      assert {:ok, player} = Bingos.ensure_player(event, "attendee-1", %{"name" => "Avery"})
      assert player.name == "Avery"
      assert byte_size(player.code) == 6

      assert {:ok, updated} = Bingos.ensure_player(event, "attendee-1", %{"name" => "Riley"})
      assert updated.id == player.id
      assert updated.name == "Riley"
      assert updated.code == player.code
    end

    test "connect_player/3 saves a connection and advances the current prompt" do
      event = event_fixture()
      first = bingo_prompt_fixture(%{event: event, prompt: "Meet a founder"})
      second = bingo_prompt_fixture(%{event: event, prompt: "Meet a designer"})

      player =
        bingo_player_fixture(%{event: event, attendee_identifier: "attendee-a", name: "Avery"})

      target =
        bingo_player_fixture(%{event: event, attendee_identifier: "attendee-b", name: "Riley"})

      assert Bingos.current_prompt(event.id, player).id == first.id

      assert {:ok, connection} = Bingos.connect_player(event.id, "attendee-a", target.code)
      assert connection.prompt.id == first.id
      assert connection.connected_player.name == "Riley"
      assert Bingos.current_prompt(event.id, player).id == second.id
      assert [saved] = Bingos.list_connections_for_player(target)
      assert saved.player.name == "Avery"
    end

    test "connect_player/3 rejects self, duplicate pairings, unknown codes, and complete cards" do
      event = event_fixture()
      bingo_prompt_fixture(%{event: event})
      player = bingo_player_fixture(%{event: event, attendee_identifier: "attendee-a"})
      target = bingo_player_fixture(%{event: event, attendee_identifier: "attendee-b"})

      assert {:error, :self_connection} =
               Bingos.connect_player(event.id, "attendee-a", player.code)

      assert {:error, :not_found} = Bingos.connect_player(event.id, "attendee-a", "missing")

      assert {:ok, _connection} = Bingos.connect_player(event.id, "attendee-a", target.code)

      assert {:error, :duplicate_connection} =
               Bingos.connect_player(event.id, "attendee-b", player.code)

      assert {:error, :complete} = Bingos.connect_player(event.id, "attendee-a", target.code)
    end
  end

  describe "settings and profiles" do
    test "get_or_create_settings/1 creates default Bingo settings once per event" do
      event = event_fixture()

      settings = Bingos.get_or_create_settings(event.id)

      assert %BingoSetting{} = settings
      refute settings.leaderboard_enabled
      assert settings.forum_enabled
      assert settings.contact_sharing_enabled

      assert settings.id == Bingos.get_or_create_settings(event.id).id
    end

    test "update_settings/2 changes organizer-controlled feature toggles" do
      event = event_fixture()
      settings = Bingos.get_or_create_settings(event.id)

      assert {:ok, updated} =
               Bingos.update_settings(settings, %{
                 leaderboard_enabled: true,
                 forum_enabled: false,
                 contact_sharing_enabled: false
               })

      assert updated.leaderboard_enabled
      refute updated.forum_enabled
      refute updated.contact_sharing_enabled
    end

    test "profile changesets validate contact fields and normalize urls" do
      event = event_fixture()

      assert {:error, changeset} =
               Bingos.create_player(%{
                 event_id: event.id,
                 attendee_identifier: "attendee-a",
                 name: "Avery",
                 email: "not an email",
                 linkedin_url: "ftp://linkedin.com/in/avery",
                 website_url: "website"
               })

      assert "must be a valid email address" in errors_on(changeset).email
      assert "must be a LinkedIn URL" in errors_on(changeset).linkedin_url

      assert {:ok, player} =
               Bingos.create_player(%{
                 event_id: event.id,
                 attendee_identifier: "attendee-b",
                 name: "Riley",
                 website_url: "riley.example.com"
               })

      assert player.website_url == "https://riley.example.com"
    end

    test "shared_profile/2 only returns fields opted into by the attendee" do
      event = event_fixture()
      settings = Bingos.get_or_create_settings(event.id)

      player =
        bingo_player_fixture(%{
          event: event,
          name: "Avery",
          title: "Founder",
          company: "CoreOrbit",
          intro: "I build event tools.",
          email: "avery@example.com",
          phone: "555-111-2222",
          linkedin_url: "https://linkedin.com/in/avery",
          website_url: "https://coreorbit.io",
          share_title: true,
          share_company: true,
          share_intro: false,
          share_email: true,
          share_phone: false,
          share_linkedin_url: true,
          share_website_url: false
        })

      profile = Bingos.shared_profile(player, settings)

      assert profile.name == "Avery"
      assert profile.title == "Founder"
      assert profile.company == "CoreOrbit"
      assert profile.email == "avery@example.com"
      assert profile.linkedin_url == "https://linkedin.com/in/avery"
      refute Map.has_key?(profile, :intro)
      refute Map.has_key?(profile, :phone)
      refute Map.has_key?(profile, :website_url)

      {:ok, settings} = Bingos.update_settings(settings, %{contact_sharing_enabled: false})

      assert %{id: player.id, name: "Avery", code: player.code} ==
               Bingos.shared_profile(player, settings)
    end
  end

  describe "forum, leaderboard, dashboard, and export" do
    test "list_forum_players/1 returns public introductions without contact fields" do
      event = event_fixture()

      player =
        bingo_player_fixture(%{
          event: event,
          name: "Avery",
          title: "Founder",
          company: "CoreOrbit",
          intro: "Ask me about event networking.",
          email: "avery@example.com",
          share_email: true
        })

      [forum_profile] = Bingos.list_forum_players(event.id)

      assert forum_profile.id == player.id
      assert forum_profile.name == "Avery"
      assert forum_profile.intro == "Ask me about event networking."
      refute Map.has_key?(forum_profile, :email)

      settings = Bingos.get_or_create_settings(event.id)
      {:ok, _settings} = Bingos.update_settings(settings, %{forum_enabled: false})

      assert [] == Bingos.list_forum_players(event.id)
    end

    test "leaderboard, dashboard stats, and export rows reflect Bingo progress" do
      event = event_fixture()
      first = bingo_prompt_fixture(%{event: event, prompt: "Find a founder"})
      second = bingo_prompt_fixture(%{event: event, prompt: "Find a designer"})

      avery =
        bingo_player_fixture(%{
          event: event,
          attendee_identifier: "attendee-a",
          name: "Avery",
          email: "avery@example.com",
          phone: "555-111-2222",
          share_email: true,
          share_phone: false
        })

      riley =
        bingo_player_fixture(%{event: event, attendee_identifier: "attendee-b", name: "Riley"})

      casey =
        bingo_player_fixture(%{event: event, attendee_identifier: "attendee-c", name: "Casey"})

      assert {:ok, _} = Bingos.connect_player(event.id, "attendee-a", riley.code)
      assert {:ok, _} = Bingos.connect_player(event.id, "attendee-a", casey.code)
      assert {:ok, _} = Bingos.connect_player(event.id, "attendee-b", casey.code)

      avery_id = avery.id

      assert [
               %{player_id: ^avery_id, name: "Avery", completed_prompts: 2},
               %{player_id: _, name: "Riley", completed_prompts: 1},
               %{player_id: _, name: "Casey", completed_prompts: 0}
             ] = Bingos.leaderboard(event.id)

      stats = Bingos.dashboard_stats(event.id)

      assert stats.player_count == 3
      assert stats.prompt_count == 2
      assert stats.connection_count == 3
      assert stats.completed_count == 1
      assert stats.completion_rate == 33

      assert [
               %{prompt_id: first.id, prompt: "Find a founder", connection_count: 2},
               %{prompt_id: second.id, prompt: "Find a designer", connection_count: 1}
             ] == stats.prompt_performance

      {headers, rows} = Bingos.export_players_rows(event.id)
      avery_row = Enum.find(rows, fn row -> Enum.at(row, 0) == "Avery" end)

      assert "Email" in headers
      assert "Phone" in headers
      assert "avery@example.com" in avery_row
      refute "555-111-2222" in avery_row
    end
  end
end
