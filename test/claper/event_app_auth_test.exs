defmodule Claper.EventAppAuthTest do
  use Claper.DataCase

  import Claper.{
    AgendasFixtures,
    BingosFixtures,
    EventsFixtures,
    FormsFixtures,
    PollsFixtures,
    PresentationsFixtures,
    QuizzesFixtures
  }

  alias Claper.{EventApp, Forms, Polls, Posts, Quizzes}
  alias Claper.EventApp.{Attendee, Notifications, OtpChallenge, Session}
  alias Claper.HiEvents
  alias Claper.HiEvents.EventTicket

  describe "attendee OTP login" do
    test "creates a hashed code challenge for an active synced ticket" do
      event = event_fixture()
      ticket = ticket_fixture(event, %{attendee_email: "Avery@Example.com"})

      assert {:ok, %{challenge: challenge, delivery_status: "disabled"}} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert challenge.event_id == event.id
      assert challenge.email == "avery@example.com"
      assert challenge.delivery_status == "disabled"
      assert challenge.expires_at
      refute challenge.code_hash =~ "4821"
      assert ticket.id
    end

    test "rejects login when no synced active ticket exists" do
      event = event_fixture()

      assert {:error, :ticket_not_found} =
               EventApp.request_login_code(event.code, "missing@example.com", code: "4821")

      assert Repo.aggregate(
               from(challenge in OtpChallenge, where: challenge.event_id == ^event.id),
               :count
             ) == 0
    end

    test "verifies a code and creates an attendee session" do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com", attendee_name: "Avery Singh"})

      assert {:ok, %{challenge: challenge}} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{attendee: attendee, token: token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      assert attendee.email == "avery@example.com"
      assert attendee.name == "Avery Singh"
      assert {:ok, _uuid} = Ecto.UUID.cast(attendee.interaction_key)
      assert is_binary(token)

      assert Repo.get!(OtpChallenge, challenge.id).status == "verified"

      assert Repo.aggregate(
               from(attendee in Attendee, where: attendee.event_id == ^event.id),
               :count
             ) == 1

      assert Repo.aggregate(
               from(session in Session, where: session.event_id == ^event.id),
               :count
             ) == 1

      assert {:ok, bootstrap} = EventApp.bootstrap_event(event.code, token)
      assert bootstrap.attendee.authenticated
      assert bootstrap.attendee.email == "avery@example.com"
    end

    test "keeps one stable interaction identity across repeated OTP sessions" do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{attendee: first_attendee, token: first_token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      Repo.update_all(
        from(challenge in OtpChallenge, where: challenge.event_id == ^event.id),
        set: [inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -120, :second)]
      )

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "5932")

      assert {:ok, %{attendee: second_attendee, token: second_token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "5932")

      refute first_token == second_token
      assert first_attendee.id == second_attendee.id
      assert first_attendee.interaction_key == second_attendee.interaction_key

      assert {:ok, identity} = EventApp.interaction_identity(event.id, second_token)
      assert identity.attendee.id == first_attendee.id
      assert identity.interaction_key == first_attendee.interaction_key
    end

    test "claims a legacy Bingo identity without replacing an existing stable player" do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{attendee: attendee}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      legacy_player =
        bingo_player_fixture(%{
          event: event,
          attendee_identifier: "legacy-session-token",
          name: "Avery"
        })

      assert {:ok, %{bingo_player: claimed}} =
               EventApp.claim_legacy_identity(event.id, attendee, "legacy-session-token")

      assert claimed.id == legacy_player.id
      assert claimed.attendee_identifier == attendee.interaction_key

      assert {:ok, %{bingo_player: same_player}} =
               EventApp.claim_legacy_identity(event.id, attendee, "legacy-session-token")

      assert same_player.id == legacy_player.id
    end

    test "claims legacy interaction rows into the stable identity" do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})
      presentation_file = presentation_file_fixture(%{event: event})
      poll = poll_fixture(%{presentation_file_id: presentation_file.id})
      quiz = quiz_fixture(%{presentation_file: presentation_file})
      form = form_fixture(%{presentation_file_id: presentation_file.id})
      legacy_identifier = "legacy-session-token"

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{attendee: attendee}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      assert {:ok, _poll} =
               Polls.vote(legacy_identifier, event.uuid, [List.first(poll.poll_opts)], poll.id)

      quiz_option =
        quiz.quiz_questions |> List.first() |> Map.get(:quiz_question_opts) |> List.first()

      assert {:ok, _quiz} =
               Quizzes.submit_quiz(legacy_identifier, event.uuid, [quiz_option], quiz.id)

      assert {:ok, _submit} =
               Forms.create_or_update_form_submit(event.uuid, %{
                 "attendee_identifier" => legacy_identifier,
                 "form_id" => form.id,
                 "response" => %{"Name" => "Avery"}
               })

      assert {:ok, post} =
               Posts.create_post(event, %{
                 body: "What should founders know?",
                 attendee_identifier: legacy_identifier,
                 name: "Avery",
                 position: 0
               })

      assert {:ok, :added, _post} =
               Posts.toggle_attendee_reaction(event.id, legacy_identifier, post.uuid, "👍")

      assert {:ok, %{claimed: claimed}} =
               EventApp.claim_legacy_identity(event.id, attendee, legacy_identifier)

      assert claimed == %{
               poll_votes: 1,
               quiz_responses: 1,
               form_submits: 1,
               posts: 1,
               reactions: 1
             }

      assert length(Polls.get_poll_vote(attendee.interaction_key, poll.id)) == 1
      assert length(Quizzes.get_quiz_responses(attendee.interaction_key, quiz.id)) == 1
      assert Forms.get_form_submit(attendee.interaction_key, form.id)
      assert Polls.get_poll_vote(legacy_identifier, poll.id) == []
      assert Quizzes.get_quiz_responses(legacy_identifier, quiz.id) == []
      assert is_nil(Forms.get_form_submit(legacy_identifier, form.id))
      assert Repo.get!(Claper.Posts.Post, post.id).attendee_identifier == attendee.interaction_key

      assert Repo.get_by!(Claper.Posts.Reaction, post_id: post.id).attendee_identifier ==
               attendee.interaction_key
    end

    test "returns a safe ticket wallet for a signed-in attendee" do
      event = event_fixture()

      ticket_fixture(event, %{
        attendee_email: "avery@example.com",
        attendee_name: "Avery Singh",
        external_ticket_id: "ticket_public_1",
        raw_payload: %{"secret" => "hidden"}
      })

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{token: token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      assert {:ok, wallet} = EventApp.ticket_wallet(event.id, token)

      assert wallet.attendee_name == "Avery Singh"
      assert wallet.attendee_email == "avery@example.com"
      assert wallet.ticket_name == "Builder Pass"
      assert wallet.reference == "ticket_public_1"
      refute Map.has_key?(wallet, :raw_payload)
    end

    test "wallet QR value prefers the Hi.Events attendee public_id" do
      event = event_fixture()

      ticket_fixture(event, %{
        attendee_email: "avery@example.com",
        external_public_id: "attendee-public-99",
        external_ticket_id: "ticket_internal_9"
      })

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{token: token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      assert {:ok, wallet} = EventApp.ticket_wallet(event.id, token)
      assert wallet.qr_value == "attendee-public-99"
    end

    test "wallet QR value falls back to the ticket reference without a public_id" do
      event = event_fixture()

      ticket_fixture(event, %{
        attendee_email: "avery@example.com",
        external_ticket_id: "ticket_internal_10"
      })

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{token: token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      assert {:ok, wallet} = EventApp.ticket_wallet(event.id, token)
      assert wallet.qr_value == "ticket_internal_10"
    end

    test "toggles saved agenda sessions for a signed-in attendee" do
      event = event_fixture()
      agenda_item = agenda_item_fixture(%{event: event, title: "Investor meetup"})
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:ok, %{token: token}} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      assert EventApp.list_bookmarked_agenda_item_ids(event.id, token) == MapSet.new()
      assert {:ok, :saved} = EventApp.toggle_agenda_bookmark(event.id, token, agenda_item.id)

      assert MapSet.member?(
               EventApp.list_bookmarked_agenda_item_ids(event.id, token),
               agenda_item.id
             )

      assert {:ok, :removed} = EventApp.toggle_agenda_bookmark(event.id, token, agenda_item.id)

      refute MapSet.member?(
               EventApp.list_bookmarked_agenda_item_ids(event.id, token),
               agenda_item.id
             )
    end

    test "increments attempts and locks after too many invalid codes" do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, %{challenge: challenge}} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      for _ <- 1..4 do
        assert {:error, :invalid_code} =
                 EventApp.verify_login_code(event.code, "avery@example.com", "1111")
      end

      assert {:error, :too_many_attempts} =
               EventApp.verify_login_code(event.code, "avery@example.com", "1111")

      challenge = Repo.get!(OtpChallenge, challenge.id)
      assert challenge.status == "locked"
      assert challenge.attempts_count == 5
    end

    test "rejects expired codes" do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, %{challenge: challenge}} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      challenge
      |> Ecto.Changeset.change(
        expires_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      assert {:error, :code_expired} =
               EventApp.verify_login_code(event.code, "avery@example.com", "4821")

      assert Repo.get!(OtpChallenge, challenge.id).status == "expired"
    end

    test "prevents rapid repeated code requests" do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      assert {:error, :too_soon} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4822")
    end
  end

  describe "n8n payloads" do
    test "builds a signed attendee OTP delivery payload" do
      event = event_fixture()
      ticket = ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, %{challenge: challenge}} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      payload = Notifications.attendee_otp_payload(event, ticket, challenge, "4821")

      body = Jason.encode!(payload)
      signature = Notifications.signature("secret", body)

      assert payload.type == "attendee_otp"
      assert payload.event_code == event.code
      assert payload.email == "avery@example.com"
      assert payload.otp_code == "4821"
      assert payload.app_url =~ "/app/#{event.code}"
      assert payload.verify_url =~ "/app/#{event.code}/verify"
      assert payload.verify_url =~ "email=avery%40example.com"
      assert byte_size(signature) == 64
    end

    test "uses the public app base URL for the configured vanity event" do
      event = event_fixture()
      ticket = ticket_fixture(event, %{attendee_email: "avery@example.com"})
      original_config = Application.get_env(:claper, :event_app, [])

      Application.put_env(
        :claper,
        :event_app,
        original_config
        |> Keyword.put(:public_event_code, event.code)
        |> Keyword.put(:public_base_url, "https://app.nextgensummit.co")
      )

      on_exit(fn ->
        Application.put_env(:claper, :event_app, original_config)
      end)

      assert {:ok, %{challenge: challenge}} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      payload = Notifications.attendee_otp_payload(event, ticket, challenge, "4821")

      assert payload.app_url == "https://app.nextgensummit.co"
      assert payload.verify_url == "https://app.nextgensummit.co/verify?email=avery%40example.com"
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
end
