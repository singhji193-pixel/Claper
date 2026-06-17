defmodule ClaperWeb.EventLiveTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{AgendasFixtures, BingosFixtures, PresentationsFixtures}

  alias Claper.Agendas
  alias Claper.Bingos
  alias Claper.Repo

  @update_attrs %{name: "some updated name"}

  defp create_event(params) do
    presentation_file = presentation_file_fixture(%{user: params.user}, [:event])
    presentation_state_fixture(%{presentation_file: presentation_file})
    params |> Map.put(:presentation_file, presentation_file)
  end

  describe "Index" do
    setup [:register_and_log_in_user, :create_event]

    test "lists all events", %{conn: conn, presentation_file: presentation_file} do
      {:ok, _index_live, html} = live(conn, ~p"/events")

      assert html =~ "events"
      assert html =~ presentation_file.event.name
    end

    test "shows agenda management link in event actions", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      {:ok, _index_live, html} = live(conn, ~p"/events")

      assert html =~ "Agenda"
      assert html =~ ~p"/e/#{presentation_file.event.code}/manage/agenda"
      assert html =~ "Bingo"
      assert html =~ ~p"/e/#{presentation_file.event.code}/manage/bingo"
    end

    test "updates event in listing", %{conn: conn, presentation_file: presentation_file} do
      {:ok, index_live, _html} = live(conn, ~p"/events/#{presentation_file.event.uuid}/edit")

      {:ok, conn} =
        index_live
        |> form("#event-form", event: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, ~p"/events")

      assert html_response(conn, 200) =~ "Updated successfully"
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "deletes event in listing", %{conn: conn, presentation_file: presentation_file} do
      {:ok, index_live, _html} = live(conn, ~p"/events/#{presentation_file.event.uuid}/edit")

      {:ok, conn} =
        index_live
        |> element(~s{a[phx-value-id=#{presentation_file.event.uuid}]})
        |> render_click()
        |> follow_redirect(conn, ~p"/events")

      {:ok, index_live, _html} = live(conn, ~p"/events")

      refute has_element?(index_live, "#event-#{presentation_file.event.uuid}")
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user, :create_event]

    test "displays event", %{conn: conn, presentation_file: presentation_file} do
      {:ok, _show_live, html} =
        live(conn, ~p"/e/#{presentation_file.event.code}")

      assert html =~ "Be the first to react !"
      assert html =~ presentation_file.event.name
    end

    test "shows agenda link in the audience hamburger menu", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      {:ok, _show_live, html} = live(conn, ~p"/e/#{presentation_file.event.code}")

      assert html =~ "Agenda"
      assert html =~ ~p"/e/#{presentation_file.event.code}/agenda"
      assert html =~ "Bingo"
      assert html =~ ~p"/e/#{presentation_file.event.code}/bingo"
    end
  end

  describe "PWA shell" do
    setup [:register_and_log_in_user, :create_event]

    test "displays the modern event app shell with bottom navigation", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      agenda_item_fixture(%{event: event, title: "Opening session"})
      bingo_prompt_fixture(%{event: event, prompt: "Find another founder"})

      {:ok, _pwa_live, html} = live(conn, ~p"/app/#{event.code}")

      assert html =~ "NextGen event app"
      assert html =~ event.name
      assert html =~ "Agenda"
      assert html =~ "Bingo"
      assert html =~ "People"
      assert html =~ "Profile"
      assert html =~ ~p"/app/#{event.code}/agenda"
      assert html =~ ~p"/app/#{event.code}/bingo"
    end

    test "renders agenda items inside the PWA shell", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      agenda_item_fixture(%{
        event: event,
        starts_at: ~N[2026-06-01 09:00:00],
        title: "Opening keynote",
        speaker_name: "Avery Singh",
        duration_minutes: 30
      })

      {:ok, _pwa_live, html} = live(conn, ~p"/app/#{event.code}/agenda")

      assert html =~ "Opening keynote"
      assert html =~ "Avery Singh"
      assert html =~ "09:00"
      assert html =~ ~p"/e/#{event.code}/agenda"
    end

    test "shows a designed unavailable state for missing events", %{conn: conn} do
      {:ok, _pwa_live, html} = live(conn, ~p"/app/missing")

      assert html =~ "Event not found"
      assert html =~ "Enter another code"
    end
  end

  describe "Bingo" do
    setup [:register_and_log_in_user, :create_event]

    test "lets an attendee create a player and connect with another attendee", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      bingo_prompt_fixture(%{event: event, prompt: "Find someone who loves product launches"})

      target =
        bingo_player_fixture(%{
          event: event,
          attendee_identifier: "target",
          name: "Riley",
          email: "riley@example.com",
          phone: "555-333-4444",
          linkedin_url: "https://linkedin.com/in/riley",
          share_email: true,
          share_phone: false,
          share_linkedin_url: true
        })

      {:ok, bingo_live, html} = live(conn, ~p"/e/#{event.code}/bingo")

      assert html =~ "Start Bingo"

      html =
        bingo_live
        |> form("#bingo-player-form", bingo_player: %{name: "Avery"})
        |> render_submit()

      assert html =~ "Find someone who loves product launches"
      assert html =~ "Your code"
      assert html =~ "Connections"

      html =
        bingo_live
        |> element("button[phx-value-tab='profile']")
        |> render_click()

      assert html =~ "Bingo profile"

      html =
        bingo_live
        |> form("#bingo-profile-form",
          bingo_player: %{
            name: "Avery",
            title: "Founder",
            company: "CoreOrbit",
            intro: "Ask me about event networking.",
            email: "avery@example.com",
            share_email: "true"
          }
        )
        |> render_submit()

      assert html =~ "Profile saved"

      html =
        bingo_live
        |> element("button[phx-value-tab='play']")
        |> render_click()

      assert html =~ "Find someone who loves product launches"

      html =
        bingo_live
        |> form("#bingo-connection-form", connection: %{code: target.code})
        |> render_submit()

      assert html =~ "Connected with Riley"
      assert html =~ "Bingo complete"

      html =
        bingo_live
        |> element("button[phx-value-tab='connections']")
        |> render_click()

      assert html =~ "Riley"
      assert html =~ "riley@example.com"
      assert html =~ "https://linkedin.com/in/riley"
      refute html =~ "555-333-4444"
    end

    test "shows people forum without contact fields and hides leaderboard until enabled", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      bingo_prompt_fixture(%{event: event})

      bingo_player_fixture(%{
        event: event,
        attendee_identifier: "target",
        name: "Riley",
        title: "Designer",
        company: "CoreOrbit",
        intro: "I like turning awkward rooms into conversations.",
        email: "riley@example.com",
        share_email: true
      })

      {:ok, bingo_live, _html} = live(conn, ~p"/e/#{event.code}/bingo")

      html =
        bingo_live
        |> form("#bingo-player-form", bingo_player: %{name: "Avery"})
        |> render_submit()

      refute html =~ "Leaderboard"

      html =
        bingo_live
        |> element("button[phx-value-tab='people']")
        |> render_click()

      assert html =~ "People"
      assert html =~ "I like turning awkward rooms into conversations."
      refute html =~ "riley@example.com"

      settings = Bingos.get_or_create_settings(event.id)
      {:ok, _settings} = Bingos.update_settings(settings, %{leaderboard_enabled: true})

      {:ok, bingo_live, _html} = live(conn, ~p"/e/#{event.code}/bingo")

      html =
        bingo_live
        |> form("#bingo-player-form", bingo_player: %{name: "Jordan"})
        |> render_submit()

      assert html =~ "Leaderboard"

      html =
        bingo_live
        |> element("button[phx-value-tab='leaderboard']")
        |> render_click()

      assert html =~ "Riley"
    end

    test "shows empty state when organizer has not added prompts", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      {:ok, _bingo_live, html} = live(conn, ~p"/e/#{presentation_file.event.code}/bingo")

      assert html =~ "Bingo is not ready yet"
      refute html =~ "Start Bingo"
    end
  end

  describe "Agenda" do
    setup [:register_and_log_in_user, :create_event]

    test "displays agenda items for the event in order", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      second =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 10:00:00],
          title: "Second session"
        })

      first =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 09:00:00],
          title: "First session"
        })

      {:ok, _agenda_live, html} = live(conn, ~p"/e/#{event.code}/agenda")

      assert html =~ event.name
      assert html =~ first.title
      assert html =~ second.title
      assert html =~ "Jun 01, 10:00"
    end

    test "does not expose agenda management controls to audience users", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      agenda_item_fixture(%{event: presentation_file.event})

      {:ok, _agenda_live, html} = live(conn, ~p"/e/#{presentation_file.event.code}/agenda")

      refute html =~ "New agenda item"
      refute html =~ "Edit agenda item"
      refute html =~ "Delete agenda item"
      refute html =~ "phx-click=\"delete\""
    end
  end

  describe "Owner agenda management" do
    setup [:register_and_log_in_user, :create_event]

    test "creates, edits, deletes, and reorders agenda items from the event owner flow", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      {:ok, new_live, _html} = live(conn, ~p"/e/#{event.code}/manage/agenda/new")

      {:ok, _index_live, html} =
        new_live
        |> form("#agenda-item-form",
          agenda_item: %{
            starts_at: "2026-06-01T09:00",
            title: "Opening keynote",
            description: "Welcome to the event",
            speaker_name: "Avery Singh",
            duration_minutes: "30"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/e/#{event.code}/manage/agenda")

      assert html =~ "Opening keynote"
      agenda_item = event.id |> Agendas.list_agenda_items() |> List.first()

      {:ok, edit_live, _html} =
        live(conn, ~p"/e/#{event.code}/manage/agenda/#{agenda_item}/edit")

      {:ok, _index_live, html} =
        edit_live
        |> form("#agenda-item-form",
          agenda_item: %{
            starts_at: "2026-06-01T09:30",
            title: "Updated keynote",
            description: "Updated details",
            speaker_name: "Avery Singh",
            duration_minutes: "45",
            position: agenda_item.position
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/e/#{event.code}/manage/agenda")

      assert html =~ "Updated keynote"

      first = Repo.reload!(agenda_item)
      second = agenda_item_fixture(%{event: event, title: "Second item"})

      {:ok, index_live, _html} = live(conn, ~p"/e/#{event.code}/manage/agenda")

      index_live
      |> element("button[phx-value-id='#{second.id}'][phx-value-direction='up']")
      |> render_click()

      assert [second.id, first.id] == event.id |> Agendas.list_agenda_items() |> Enum.map(& &1.id)

      index_live
      |> element("button[phx-value-id='#{first.id}'][phx-click='delete']")
      |> render_click()

      refute Repo.reload(first)
    end

    test "redirects non-owners away from agenda management", %{conn: conn} do
      other_user = Claper.AccountsFixtures.confirmed_user_fixture()
      presentation_file = presentation_file_fixture(%{user: other_user}, [:event])
      presentation_state_fixture(%{presentation_file: presentation_file})

      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, ~p"/e/#{presentation_file.event.code}/manage/agenda")
    end
  end

  describe "Owner Bingo management" do
    setup [:register_and_log_in_user, :create_event]

    test "creates, edits, deletes, and reorders Bingo prompts from the event owner flow", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      {:ok, new_live, _html} = live(conn, ~p"/e/#{event.code}/manage/bingo/new")

      {:ok, _index_live, html} =
        new_live
        |> form("#bingo-prompt-form",
          bingo_prompt: %{
            prompt: "Find someone who has hosted an event"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/e/#{event.code}/manage/bingo")

      assert html =~ "Find someone who has hosted an event"
      prompt = event.id |> Bingos.list_prompts() |> List.first()

      {:ok, edit_live, _html} =
        live(conn, ~p"/e/#{event.code}/manage/bingo/#{prompt}/edit")

      {:ok, _index_live, html} =
        edit_live
        |> form("#bingo-prompt-form",
          bingo_prompt: %{
            prompt: "Find someone who has built a community",
            position: prompt.position
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/e/#{event.code}/manage/bingo")

      assert html =~ "Find someone who has built a community"

      first = Repo.reload!(prompt)
      second = bingo_prompt_fixture(%{event: event, prompt: "Second prompt"})

      {:ok, index_live, _html} = live(conn, ~p"/e/#{event.code}/manage/bingo")

      index_live
      |> element("button[phx-value-id='#{second.id}'][phx-value-direction='up']")
      |> render_click()

      assert [second.id, first.id] == event.id |> Bingos.list_prompts() |> Enum.map(& &1.id)

      index_live
      |> element("button[phx-value-id='#{first.id}'][phx-click='delete']")
      |> render_click()

      refute Repo.reload(first)
    end

    test "updates Bingo settings and shows dashboard, QR, and export action", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      bingo_prompt_fixture(%{event: event, prompt: "Find another builder"})

      avery =
        bingo_player_fixture(%{event: event, attendee_identifier: "attendee-a", name: "Avery"})

      riley =
        bingo_player_fixture(%{event: event, attendee_identifier: "attendee-b", name: "Riley"})

      assert {:ok, _connection} = Bingos.connect_player(event.id, "attendee-a", riley.code)

      {:ok, manage_live, html} = live(conn, ~p"/e/#{event.code}/manage/bingo")

      assert html =~ "Bingo dashboard"
      assert html =~ "Attendee QR"
      assert html =~ "Export CSV"
      assert html =~ "Players"
      assert html =~ "Connections"

      html =
        manage_live
        |> form("#bingo-settings-form",
          bingo_setting: %{
            leaderboard_enabled: "true",
            forum_enabled: "false",
            contact_sharing_enabled: "false"
          }
        )
        |> render_submit()

      settings = Bingos.get_or_create_settings(event.id)
      assert settings.leaderboard_enabled
      refute settings.forum_enabled
      refute settings.contact_sharing_enabled
      assert html =~ "Settings saved"
      assert html =~ avery.name
    end

    test "redirects non-owners away from Bingo management", %{conn: conn} do
      other_user = Claper.AccountsFixtures.confirmed_user_fixture()
      presentation_file = presentation_file_fixture(%{user: other_user}, [:event])
      presentation_state_fixture(%{presentation_file: presentation_file})

      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, ~p"/e/#{presentation_file.event.code}/manage/bingo")
    end
  end
end
