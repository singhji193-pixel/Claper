# E2E seed for the NextGen Summit attendee PWA.
#
# Run inside the dev container against the dev database:
#   docker exec clapper-app-1 mix run e2e/seed.exs
#
# Idempotent: deletes and recreates the dedicated `e2e01` event only.

import Ecto.Query

alias Claper.{Accounts, Agendas, EventApp, Events, HiEvents, Polls, Presentations, Repo}
alias Claper.HiEvents.EventTicket

event_code = "e2e01"
owner_email = "e2e-owner@example.com"
owner_password = "e2e-password-123"
attendee_email = "e2e-attendee@example.com"

# --- owner user ---------------------------------------------------------

owner =
  case Accounts.get_user_by_email(owner_email) do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          email: owner_email,
          password: owner_password,
          confirmed_at: NaiveDateTime.utc_now()
        })

      user

    user ->
      user
  end

owner =
  if owner.confirmed_at do
    owner
  else
    owner
    |> Ecto.Changeset.change(
      confirmed_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    )
    |> Repo.update!()
  end

# --- reset the e2e event -------------------------------------------------

Repo.delete_all(from(e in Events.Event, where: e.code == ^event_code))

{:ok, event} =
  Events.create_event(%{
    name: "NextGen E2E Summit",
    code: event_code,
    uuid: Ecto.UUID.generate(),
    user_id: owner.id,
    # Event day: July 25 2026, 08:30 PDT stored as UTC.
    started_at: ~N[2026-07-25 15:30:00],
    expired_at: nil
  })

{:ok, presentation_file} =
  Presentations.create_presentation_file(%{
    hash: "e2e-hash",
    length: 3,
    status: "done",
    event_id: event.id
  })

{:ok, _presentation_state} =
  Presentations.create_presentation_state(%{
    presentation_file_id: presentation_file.id,
    position: 0,
    chat_enabled: true,
    poll_visible: true,
    chat_visible: true
  })

# --- event app settings --------------------------------------------------

settings = EventApp.get_or_create_settings(event.id)

{:ok, _settings} =
  EventApp.update_settings(settings, %{
    event_id: event.id,
    ticket_enabled: true,
    people_enabled: true,
    chat_enabled: true,
    live_interactions_enabled: true,
    qa_enabled: true,
    resources_enabled: true,
    timezone: "America/Vancouver"
  })

# --- Hi.Events integration and attendee ticket ---------------------------

{:ok, integration} =
  HiEvents.upsert_integration(event.id, %{"external_event_id" => "e2e_hi_events"})

%EventTicket{}
|> EventTicket.changeset(%{
  event_id: event.id,
  integration_id: integration.id,
  external_attendee_id: "e2e-attendee-1",
  external_ticket_id: "e2e-ticket-1",
  external_public_id: "e2e-public-1",
  ticket_name: "Builder Pass",
  attendee_email: attendee_email,
  attendee_first_name: "Emery",
  attendee_last_name: "Tester",
  attendee_name: "Emery Tester",
  status: "active",
  raw_payload: %{"public_id" => "e2e-public-1"}
})
|> Repo.insert!()

# --- agenda: morning + evening on the same PDT day ------------------------

{:ok, _morning} =
  Agendas.create_agenda_item(%{
    event_id: event.id,
    # 08:30 PDT
    starts_at: ~N[2026-07-25 15:30:00],
    title: "E2E Opening Keynote",
    description: "Welcome to the summit",
    speaker_name: "Jordan Keynote",
    speaker_title: "CEO",
    speaker_company: "CoreOrbit",
    location_name: "Main Stage",
    track_name: "Growth",
    session_type: "Keynote",
    duration_minutes: 45
  })

{:ok, _evening} =
  Agendas.create_agenda_item(%{
    event_id: event.id,
    # 17:15 PDT — crosses UTC midnight into July 26.
    starts_at: ~N[2026-07-26 00:15:00],
    title: "E2E Evening Reception",
    description: "Networking reception",
    speaker_name: nil,
    location_name: "Atrium",
    track_name: "Networking",
    session_type: "Social",
    duration_minutes: 105
  })

# --- active poll for the Live bridge --------------------------------------

{:ok, poll} =
  Polls.create_poll(%{
    presentation_file_id: presentation_file.id,
    title: "E2E favourite track?",
    position: 0,
    multiple: false,
    enabled: false,
    poll_opts: [
      %{content: "Growth", vote_count: 0},
      %{content: "Capital", vote_count: 0}
    ]
  })

{:ok, _poll} = Polls.set_enabled(poll.id)

# --- disabled quiz, form, and embed for the manager bridge tests -----------

{:ok, _quiz} =
  Claper.Quizzes.create_quiz(%{
    presentation_file_id: presentation_file.id,
    title: "E2E summit quiz",
    position: 0,
    enabled: false,
    show_results: true,
    quiz_questions: [
      %{
        content: "Where is the summit held?",
        type: "qcm",
        quiz_question_opts: [
          %{content: "Anvil Centre", is_correct: true},
          %{content: "Moon Base", is_correct: false}
        ]
      }
    ]
  })

{:ok, _form} =
  Claper.Forms.create_form(%{
    presentation_file_id: presentation_file.id,
    title: "E2E feedback form",
    position: 0,
    enabled: false,
    fields: [
      %{name: "Full name", type: "text", required: true},
      %{name: "Work email", type: "email", required: true}
    ]
  })

{:ok, _embed} =
  Claper.Embeds.create_embed(%{
    presentation_file_id: presentation_file.id,
    title: "E2E highlight reel",
    provider: "youtube",
    content: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    position: 0,
    enabled: false,
    attendee_visibility: true
  })

IO.puts("""
E2E seed complete.
  event:    #{event.code} (id #{event.id})
  owner:    #{owner_email} / #{owner_password}
  attendee: #{attendee_email} (ticket public_id e2e-public-1)
""")
