defmodule ClaperWeb.EventLiveTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest

  import Claper.{
    AgendasFixtures,
    BingosFixtures,
    FormsFixtures,
    PollsFixtures,
    PostsFixtures,
    PresentationsFixtures,
    QuizzesFixtures
  }

  alias Claper.Agendas
  alias Claper.{Bingos, Polls}
  alias Claper.EventApp
  alias Claper.HiEvents
  alias Claper.HiEvents.EventTicket
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
      assert html =~ "Event app"
      assert html =~ ~p"/e/#{presentation_file.event.code}/manage/app"
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

    test "shows an error instead of crashing when event duplication fails", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          title: "Legacy poll",
          position: 0
        })

      Repo.update_all(from(p in Claper.Polls.Poll, where: p.id == ^poll.id), set: [position: nil])

      {:ok, index_live, _html} = live(conn, ~p"/events")

      html = render_click(index_live, "duplicate", %{"id" => presentation_file.event.uuid})

      assert html =~
               "Could not duplicate event. Please review the event interactions and try again."

      assert 0 ==
               Repo.aggregate(
                 from(e in Claper.Events.Event,
                   where:
                     e.user_id == ^presentation_file.event.user_id and
                       e.name == ^"#{presentation_file.event.name} (Copy)"
                 ),
                 :count,
                 :id
               )
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
      conn = sign_in_attendee(conn, event)

      {:ok, _pwa_live, html} = live(conn, ~p"/app/#{event.code}")

      assert html =~ "Next up"
      assert html =~ event.name
      assert html =~ "Agenda"
      assert html =~ "Bingo"
      assert html =~ "People"
      assert html =~ "Profile"
      assert html =~ ~p"/app/#{event.code}/agenda"
      assert html =~ "Scan and Bingo"
      assert html =~ ~p"/app/#{event.code}/scan"
    end

    test "redirects the vanity app host home to OTP login when signed out", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      put_public_event_code(event.code)

      conn = Map.put(conn, :host, "app.nextgensummit.co")

      assert {:error, {:redirect, %{to: "/login?next=%2F"}}} = live(conn, "/")
    end

    test "serves the vanity app host without exposing coded PWA links after OTP", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      put_public_event_code(event.code)
      agenda_item_fixture(%{event: event, title: "Opening session"})

      conn =
        conn
        |> sign_in_attendee(event)
        |> Map.put(:host, "app.nextgensummit.co")

      {:ok, _pwa_live, html} = live(conn, "/")

      assert html =~ event.name
      assert html =~ "Event app"
      assert html =~ ~s(href="/agenda")
      assert html =~ ~s(href="/scan")
      refute html =~ "/app/#{event.code}/agenda"
    end

    test "renders agenda items inside the PWA shell", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      # 16:00 UTC renders as the 09:00 PDT wall time attendees expect.
      agenda_item_fixture(%{
        event: event,
        starts_at: ~N[2026-06-01 16:00:00],
        title: "Opening keynote",
        speaker_name: "Avery Singh",
        speaker_title: "Founder",
        speaker_company: "CoreOrbit",
        location_name: "Main Stage",
        track_name: "Growth",
        session_type: "Keynote",
        duration_minutes: 30
      })

      conn = sign_in_attendee(conn, event)

      {:ok, _pwa_live, html} = live(conn, ~p"/app/#{event.code}/agenda")

      assert html =~ "Opening keynote"
      assert html =~ "Avery Singh - Founder, CoreOrbit"
      assert html =~ "Main Stage"
      assert html =~ "Growth"
      assert html =~ "09:00"
      assert html =~ "Save"
      assert html =~ ~p"/app/#{event.code}/agenda"
    end

    test "renders PWA session detail and lets signed-in attendees save a session", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      ticket_fixture(event, %{attendee_email: "avery@example.com", attendee_name: "Avery Singh"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{token: token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      agenda_item =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 09:00:00],
          title: "Investor breakfast",
          location_name: "Atrium",
          track_name: "Capital",
          session_type: "Roundtable"
        })

      settings = EventApp.get_or_create_settings(event.id)
      {:ok, _settings} = EventApp.update_settings(settings, %{resources_enabled: true})

      assert {:ok, _published} =
               Agendas.create_resource(%{
                 event_id: event.id,
                 agenda_item_id: agenda_item.id,
                 title: "Investor checklist",
                 kind: "pdf",
                 url: "https://cdn.example.com/investor-checklist.pdf",
                 published: true
               })

      assert {:ok, _draft} =
               Agendas.create_resource(%{
                 event_id: event.id,
                 agenda_item_id: agenda_item.id,
                 title: "Private draft",
                 kind: "slides",
                 url: "https://cdn.example.com/draft",
                 published: false
               })

      conn = init_test_session(conn, %{event_app_session_token: token})

      {:ok, session_live, html} = live(conn, ~p"/app/#{event.code}/agenda/#{agenda_item.id}")

      assert html =~ "Investor breakfast"
      assert html =~ "Atrium"
      assert html =~ "Roundtable / Capital"
      assert html =~ "Investor checklist"
      assert html =~ "https://cdn.example.com/investor-checklist.pdf"
      assert html =~ ~s(rel="noopener noreferrer")
      refute html =~ "Private draft"

      html =
        session_live
        |> element("button[phx-value-id='#{agenda_item.id}']")
        |> render_click()

      assert html =~ "Saved"
    end

    test "shows a designed unavailable state for missing events", %{conn: conn} do
      {:ok, _pwa_live, html} = live(conn, ~p"/app/missing")

      assert html =~ "Event not found"
      assert html =~ "Enter another code"
    end

    test "redirects signed-out attendees to OTP login", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/app/#{event.code}/profile")

      assert to == ~p"/app/#{event.code}/login?#{[next: ~p"/app/#{event.code}/profile"]}"
    end

    test "does not authenticate with a compatibility attendee identifier alone", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      conn = init_test_session(conn, %{attendee_identifier: Ecto.UUID.generate()})

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/app/#{event.code}/profile")
      assert to == ~p"/app/#{event.code}/login?#{[next: ~p"/app/#{event.code}/profile"]}"
    end

    test "renders native Live, tracks stable Presence, and refreshes from PubSub", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      settings = EventApp.get_or_create_settings(event.id)
      {:ok, _settings} = EventApp.update_settings(settings, %{live_interactions_enabled: true})

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          enabled: true,
          title: "Opening poll"
        })

      conn = sign_in_attendee(conn, event)
      token = get_session(conn, :event_app_session_token)
      {:ok, identity} = EventApp.interaction_identity(event.id, token)

      {:ok, live_view, html} = live(conn, ~p"/app/#{event.code}/live")

      assert html =~ "Opening poll"
      assert html =~ "Interact"
      assert html =~ "Submit answer"

      assert Map.has_key?(
               ClaperWeb.Presence.list("event:#{event.uuid}"),
               identity.interaction_key
             )

      selected_option = List.first(poll.poll_opts)

      html =
        live_view
        |> form("#pwa-live-poll-form-#{poll.id}", %{
          "poll_id" => poll.id,
          "option_ids" => [selected_option.id]
        })
        |> render_submit()

      assert html =~ "Submitted"
      # Results render as visual bars once the vote is locked.
      assert html =~ "ngs-live-bar"
      assert length(Polls.get_poll_vote(identity.interaction_key, poll.id)) == 1

      assert {:ok, _poll} = Polls.update_poll(event.uuid, poll, %{title: "Updated poll"})
      assert render(live_view) =~ "Updated poll"
    end

    test "shows the contextual Live card and banner without changing bottom navigation", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      settings = EventApp.get_or_create_settings(event.id)
      {:ok, _settings} = EventApp.update_settings(settings, %{live_interactions_enabled: true})

      poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        enabled: true,
        title: "Live audience check-in"
      })

      conn = sign_in_attendee(conn, event)
      {:ok, _home, html} = live(conn, ~p"/app/#{event.code}")

      # Home shows the Live card only; the compact banner would duplicate it.
      assert html =~ "ngs-live-home-card"
      refute html =~ "ngs-live-banner"
      assert html =~ "Live audience check-in"
      assert html =~ "ngs-bottomnav"

      {:ok, _agenda, agenda_html} = live(conn, ~p"/app/#{event.code}/agenda")

      assert agenda_html =~ "ngs-live-banner"
      assert agenda_html =~ "Live audience check-in"

      # Kind-specific verb CTAs guide first-time attendees.
      assert html =~ "Vote now"
      assert agenda_html =~ "Vote now"
    end

    test "merges the LIVE badge into the tab row without an app bar", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      settings = EventApp.get_or_create_settings(event.id)
      {:ok, _settings} = EventApp.update_settings(settings, %{live_interactions_enabled: true})

      poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        enabled: true,
        title: "Header merge poll"
      })

      conn = sign_in_attendee(conn, event)
      {:ok, _live_view, html} = live(conn, ~p"/app/#{event.code}/live")

      refute html =~ "ngs-appbar-title"
      assert html =~ "ngs-live-badge"
      assert html =~ "ngs-live-tabs"
    end

    test "auto-switches to Interact when a new interaction activates and flags unread tabs", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      settings = EventApp.get_or_create_settings(event.id)

      {:ok, _settings} =
        EventApp.update_settings(settings, %{
          live_interactions_enabled: true,
          qa_enabled: true,
          chat_enabled: true
        })

      presentation_file = Repo.preload(presentation_file, :presentation_state)

      {:ok, _state} =
        Claper.Presentations.update_presentation_state(
          presentation_file.presentation_state,
          %{chat_enabled: true}
        )

      conn = sign_in_attendee(conn, event)
      {:ok, live_view, _html} = live(conn, ~p"/app/#{event.code}/live")

      # Attendee reads chat while nothing is active.
      html = live_view |> element("button[phx-value-tab='chat']") |> render_click()
      assert html =~ "Session chat"

      # Presenter opens a poll: attendee is brought to Interact automatically.
      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          enabled: true,
          title: "Auto-jump poll"
        })

      Phoenix.PubSub.broadcast(
        Claper.PubSub,
        "event:#{event.uuid}",
        {:poll_updated, poll}
      )

      html = render(live_view)
      assert html =~ "Auto-jump poll"
      assert html =~ "Submit answer"

      # A question posted while the attendee is on Interact flags Q&A as unread.
      post_fixture(%{
        event: event,
        kind: "question",
        body: "Unread indicator question",
        name: "Riley"
      })

      Phoenix.PubSub.broadcast(
        Claper.PubSub,
        "event:#{event.uuid}",
        {:post_created, %{event_id: event.id}}
      )

      assert render(live_view) =~ "ngs-tab-dot"
    end

    test "nudges attendees on other pages when an interaction activates", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      settings = EventApp.get_or_create_settings(event.id)
      {:ok, _settings} = EventApp.update_settings(settings, %{live_interactions_enabled: true})

      conn = sign_in_attendee(conn, event)
      {:ok, agenda_live, _html} = live(conn, ~p"/app/#{event.code}/agenda")

      poll =
        poll_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          enabled: true,
          title: "Nudge poll"
        })

      Phoenix.PubSub.broadcast(
        Claper.PubSub,
        "event:#{event.uuid}",
        {:poll_updated, poll}
      )

      html = render(agenda_live)
      assert html =~ "Nudge poll"
      assert html =~ "Vote now"
    end

    test "shows Live to an already-connected attendee when an organizer enables it", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      settings = EventApp.get_or_create_settings(event.id)

      poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        enabled: true,
        title: "Event-day activation poll"
      })

      conn = sign_in_attendee(conn, event)
      token = get_session(conn, :event_app_session_token)
      {:ok, identity} = EventApp.interaction_identity(event.id, token)
      {:ok, home_live, html} = live(conn, ~p"/app/#{event.code}")

      refute html =~ "ngs-live-home-card"

      assert Map.has_key?(
               ClaperWeb.Presence.list("event:#{event.uuid}"),
               identity.interaction_key
             )

      assert {:ok, _settings} =
               EventApp.update_settings(settings, %{live_interactions_enabled: true})

      Phoenix.PubSub.broadcast(
        Claper.PubSub,
        "event:#{event.uuid}",
        {:state_updated, :app_settings}
      )

      assert render(home_live) =~ "Event-day activation poll"
      assert render(home_live) =~ "ngs-live-home-card"
    end

    test "submits native Quiz and Form interactions", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      settings = EventApp.get_or_create_settings(event.id)
      {:ok, _settings} = EventApp.update_settings(settings, %{live_interactions_enabled: true})
      conn = sign_in_attendee(conn, event)
      token = get_session(conn, :event_app_session_token)
      {:ok, identity} = EventApp.interaction_identity(event.id, token)

      quiz =
        quiz_fixture(%{
          presentation_file: presentation_file,
          position: 0,
          enabled: true,
          title: "Session quiz"
        })

      question = List.first(quiz.quiz_questions)
      option = List.first(question.quiz_question_opts)
      {:ok, live_view, html} = live(conn, ~p"/app/#{event.code}/live")
      assert html =~ "Session quiz"
      assert html =~ "Lock answer"

      html =
        live_view
        |> form("#pwa-live-quiz-form-#{quiz.id}-#{question.id}", %{
          "quiz_id" => quiz.id,
          "option_ids" => [option.id]
        })
        |> render_submit()

      refute html =~ "Lock answer"
      assert length(Claper.Quizzes.get_quiz_responses(identity.interaction_key, quiz.id)) == 1

      assert {:ok, _quiz} = Claper.Quizzes.set_disabled(quiz.id)

      form =
        form_fixture(%{
          presentation_file_id: presentation_file.id,
          position: 0,
          enabled: true,
          title: "Session feedback"
        })

      Phoenix.PubSub.broadcast(
        Claper.PubSub,
        "event:#{event.uuid}",
        {:current_interaction, form}
      )

      assert render(live_view) =~ "Session feedback"

      html =
        live_view
        |> form("#pwa-live-form-#{form.id}", %{
          "form_id" => form.id,
          "response" => %{"Name" => "Avery"}
        })
        |> render_submit()

      assert html =~ "Saved"
      assert Claper.Forms.get_form_submit(identity.interaction_key, form.id)
    end

    test "keeps native Q&A and Chat separate while using Claper posts", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      settings = EventApp.get_or_create_settings(event.id)

      {:ok, _settings} =
        EventApp.update_settings(settings, %{
          live_interactions_enabled: true,
          qa_enabled: true,
          chat_enabled: true
        })

      presentation_file =
        Claper.Presentations.get_presentation_file!(presentation_file.id, [:presentation_state])

      assert {:ok, _state} =
               Claper.Presentations.update_presentation_state(
                 presentation_file.presentation_state,
                 %{chat_enabled: true, anonymous_chat_enabled: false}
               )

      conn = sign_in_attendee(conn, event)
      {:ok, live_view, _html} = live(conn, ~p"/app/#{event.code}/live")

      html =
        live_view
        |> element("button[phx-value-tab='qa']")
        |> render_click()

      assert html =~ "Session Q&amp;A"
      assert html =~ "Ask question"

      html =
        live_view
        |> form("#pwa-live-question-form", %{
          "kind" => "question",
          "body" => "How can founders participate?"
        })
        |> render_submit()

      assert html =~ "How can founders participate?"
      question = Claper.Posts.list_questions(event.uuid) |> List.first()
      assert question.kind == "question"
      assert question.name == "Avery Singh"

      html =
        live_view
        |> element("#pwa-live-post-#{question.uuid} button[phx-click='live-toggle-reaction']")
        |> render_click()

      assert html =~ ">1<"

      html =
        live_view
        |> element("button[phx-value-tab='chat']")
        |> render_click()

      assert html =~ "Session chat"
      assert html =~ "Send message"
      refute html =~ "Post anonymously"

      html =
        live_view
        |> form("#pwa-live-message-form", %{
          "kind" => "message",
          "body" => "Great session"
        })
        |> render_submit()

      assert html =~ "Great session"

      # Own message renders as a right-aligned bubble with a timestamp.
      assert html =~ "is-mine"
      assert html =~ "ngs-post-time"

      assert [%{kind: "message"} = message] =
               Claper.Posts.list_posts_by_kind(event.uuid, "message")

      html =
        live_view
        |> element(~s(#pwa-live-post-#{message.uuid} button[aria-label="Like"]))
        |> render_click()

      assert html =~ ">1<"
      assert [%{like_count: 1}] = Claper.Posts.list_posts_by_kind(event.uuid, "message")

      html =
        live_view
        |> element(~s(#pwa-live-post-#{message.uuid} button[aria-label="Heart"]))
        |> render_click()

      assert html =~ ">1<"
      assert [%{love_count: 1}] = Claper.Posts.list_posts_by_kind(event.uuid, "message")

      html =
        live_view
        |> element(~s(#pwa-live-post-#{message.uuid} button[aria-label="Laugh"]))
        |> render_click()

      assert html =~ ">1<"
      assert [%{lol_count: 1}] = Claper.Posts.list_posts_by_kind(event.uuid, "message")
    end

    test "serves native Live through the vanity app route", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      put_public_event_code(event.code)
      settings = EventApp.get_or_create_settings(event.id)
      {:ok, _settings} = EventApp.update_settings(settings, %{live_interactions_enabled: true})

      poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        enabled: true,
        title: "Vanity route poll"
      })

      conn = conn |> sign_in_attendee(event) |> Map.put(:host, "app.nextgensummit.co")

      {:ok, _live_view, html} = live(conn, "/live")
      assert html =~ "Vanity route poll"
      refute html =~ "/app/#{event.code}/live"
    end

    test "shows a verified ticket profile for signed-in attendees", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      ticket_fixture(event, %{attendee_email: "avery@example.com", attendee_name: "Avery Singh"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{token: token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      conn = init_test_session(conn, %{event_app_session_token: token})

      {:ok, _pwa_live, html} = live(conn, ~p"/app/#{event.code}/profile")

      assert html =~ "Ticket access"
      assert html =~ "Verified attendee"
      assert html =~ "Avery Singh"
      assert html =~ "Builder Pass"
      assert html =~ "Open ticket"
      assert html =~ "Sign out"
    end

    test "renders a real ticket QR without unavailable wallet controls", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      ticket =
        ticket_fixture(event, %{
          attendee_email: "avery@example.com",
          attendee_name: "Avery Singh"
        })

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{token: token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      conn = init_test_session(conn, %{event_app_session_token: token})

      {:ok, _pwa_live, html} = live(conn, ~p"/app/#{event.code}/ticket")

      assert html =~ ~s(id="pwa-ticket-qr")
      assert html =~ ~s(phx-hook="QRCode")
      assert html =~ ticket.external_ticket_id
      refute html =~ "Apple Wallet"
      refute html =~ "Brighten"
    end

    test "creates a Bingo profile in the PWA without exposing the attendee session token", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      bingo_prompt_fixture(%{event: event, prompt: "Meet someone building with AI"})
      conn = sign_in_attendee(conn, event)
      token = get_session(conn, :event_app_session_token)
      {:ok, identity} = EventApp.interaction_identity(event.id, token)

      {:ok, scan_live, html} = live(conn, ~p"/app/#{event.code}/scan")

      assert html =~ "Create your networking card"
      refute html =~ String.upcase(String.slice(token, 0, 6))

      html =
        scan_live
        |> form("#pwa-bingo-profile-form", bingo_player: %{name: "Avery Singh"})
        |> render_submit()

      player = Bingos.get_player(event.id, identity.interaction_key)

      assert player.name == "Avery Singh"
      assert html =~ player.code
      assert html =~ ~s(id="pwa-bingo-player-qr")
      assert html =~ ~s(phx-hook="QRCode")
      refute html =~ String.upcase(String.slice(token, 0, 6))
    end

    test "shows opted-in Bingo introductions in the PWA people directory", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      bingo_player_fixture(%{
        event: event,
        attendee_identifier: "riley-session",
        name: "Riley Chen",
        title: "Founder",
        company: "Northstar Labs",
        intro: "Building climate intelligence for cities"
      })

      conn = sign_in_attendee(conn, event)

      {:ok, _people_live, html} = live(conn, ~p"/app/#{event.code}/people")

      assert html =~ "Riley Chen"
      assert html =~ "Founder"
      assert html =~ "Northstar Labs"
      assert html =~ "Building climate intelligence for cities"
      refute html =~ "People discovery is queued"
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

      # Stored as naive UTC; displayed in the event timezone (PDT, UTC-7).
      second =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 17:00:00],
          title: "Second session"
        })

      first =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 16:00:00],
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

    test "stores organizer wall time as UTC and displays event-local times", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      {:ok, new_live, _html} = live(conn, ~p"/e/#{event.code}/manage/agenda/new")

      {:ok, _index_live, html} =
        new_live
        |> form("#agenda-item-form",
          agenda_item: %{
            starts_at: "2026-07-25T08:30",
            title: "Timezone check",
            duration_minutes: "30"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/e/#{event.code}/manage/agenda")

      # 08:30 PDT wall time persists as 15:30 UTC.
      agenda_item =
        event.id
        |> Agendas.list_agenda_items()
        |> Enum.find(&(&1.title == "Timezone check"))

      assert agenda_item.starts_at == ~N[2026-07-25 15:30:00]

      # The manage list shows the organizer wall time, not UTC.
      assert html =~ "2026-07-25 08:30"

      # The edit form is prefilled with the organizer wall time.
      {:ok, _edit_live, edit_html} =
        live(conn, ~p"/e/#{event.code}/manage/agenda/#{agenda_item}/edit")

      assert edit_html =~ "2026-07-25T08:30"
      refute edit_html =~ "2026-07-25T15:30"
    end

    test "redirects non-owners away from agenda management", %{conn: conn} do
      other_user = Claper.AccountsFixtures.confirmed_user_fixture()
      presentation_file = presentation_file_fixture(%{user: other_user}, [:event])
      presentation_state_fixture(%{presentation_file: presentation_file})

      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, ~p"/e/#{presentation_file.event.code}/manage/agenda")
    end

    test "manages published HTTPS resources from the Agenda editor", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      agenda_item = agenda_item_fixture(%{event: event, title: "Capital readiness"})

      {:ok, edit_live, html} =
        live(conn, ~p"/e/#{event.code}/manage/agenda/#{agenda_item}/edit")

      assert html =~ "Session resources"

      html =
        edit_live
        |> form("#agenda-resource-form",
          agenda_resource: %{
            title: "Capital worksheet",
            kind: "pdf",
            url: "https://cdn.example.com/capital.pdf",
            published: "true"
          }
        )
        |> render_submit()

      assert html =~ "Session resource saved"
      assert html =~ "Capital worksheet"
      assert html =~ "Published"

      resource = agenda_item.id |> Agendas.list_resources() |> List.first()
      assert resource.kind == "pdf"
      assert resource.published

      html =
        edit_live
        |> element("#agenda-resource-#{resource.id} button[phx-click='edit-resource']")
        |> render_click()

      assert html =~ "Edit resource"
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

  describe "Owner event app management" do
    setup [:register_and_log_in_user, :create_event]

    test "saves Hi.Events integration settings and shows webhook setup", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      {:ok, manage_live, html} = live(conn, ~p"/e/#{event.code}/manage/app")

      assert html =~ "Event app integrations"
      assert html =~ "Realtime ticket sync"
      assert html =~ "No webhook deliveries yet"

      html =
        manage_live
        |> form("#hi-events-integration-form",
          integration: %{external_event_id: "hi_evt_liveview", enabled: "true"}
        )
        |> render_submit()

      integration = HiEvents.get_integration(event.id)
      assert integration.external_event_id == "hi_evt_liveview"
      assert integration.enabled
      assert html =~ "Hi.Events integration saved"
      assert html =~ "Managed automatically"
      assert html =~ "/api/integrations/hi-events/webhook"
      assert html =~ "Signature"
      assert html =~ "Sync existing tickets"
    end

    test "saves the event timezone from the app settings form", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      {:ok, manage_live, html} = live(conn, ~p"/e/#{event.code}/manage/app")

      assert html =~ "Event timezone"
      assert html =~ "America/Vancouver"

      html =
        manage_live
        |> form("#event-app-feature-form", setting: %{timezone: "America/Toronto"})
        |> render_change()

      assert EventApp.get_or_create_settings(event.id).timezone == "America/Toronto"
      assert html =~ "Changes saved"
    end

    test "redirects non-owners away from event app management", %{conn: conn} do
      other_user = Claper.AccountsFixtures.confirmed_user_fixture()
      presentation_file = presentation_file_fixture(%{user: other_user}, [:event])
      presentation_state_fixture(%{presentation_file: presentation_file})

      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, ~p"/e/#{presentation_file.event.code}/manage/app")
    end

    test "automatically saves disabled-by-default native Live controls", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event
      {:ok, manage_live, html} = live(conn, ~p"/e/#{event.code}/manage/app")

      assert html =~ "Native attendee Live"

      html =
        manage_live
        |> form("#event-app-feature-form",
          setting: %{
            live_interactions_enabled: "true",
            qa_enabled: "true",
            chat_enabled: "false",
            resources_enabled: "true"
          }
        )
        |> render_change()

      settings = EventApp.get_settings(event.id)
      assert settings.live_interactions_enabled
      assert settings.qa_enabled
      refute settings.chat_enabled
      assert settings.resources_enabled
      assert html =~ "Changes saved"
      assert html =~ "Changes save automatically"
    end
  end

  defp ticket_fixture(event, attrs) do
    {:ok, integration} =
      HiEvents.upsert_integration(event.id, %{
        "external_event_id" => "hi_evt_#{event.id}"
      })

    attrs =
      attrs
      |> Enum.into(%{
        event_id: event.id,
        integration_id: integration.id,
        external_attendee_id: "attendee_#{System.unique_integer([:positive])}",
        external_ticket_id: "ticket_#{System.unique_integer([:positive])}",
        ticket_name: "Builder Pass",
        attendee_email: "avery@example.com",
        attendee_first_name: "Avery",
        attendee_last_name: "Singh",
        attendee_name: "Avery Singh",
        status: "active",
        raw_payload: %{}
      })

    %EventTicket{}
    |> EventTicket.changeset(attrs)
    |> Repo.insert!()
  end

  defp sign_in_attendee(conn, event, attrs \\ %{}) do
    email = Map.get(attrs, :attendee_email, "avery@example.com")
    ticket_fixture(event, Map.put_new(attrs, :attendee_email, email))

    assert {:ok, _result} = EventApp.request_login_code(event.code, email, code: "4821")
    assert {:ok, %{token: token}} = EventApp.verify_login_code(event.code, email, "4821")

    init_test_session(conn, %{event_app_session_token: token})
  end

  defp put_public_event_code(code) do
    original_config = Application.get_env(:claper, :event_app, [])

    Application.put_env(
      :claper,
      :event_app,
      Keyword.put(original_config, :public_event_code, code)
    )

    on_exit(fn ->
      Application.put_env(:claper, :event_app, original_config)
    end)
  end
end
