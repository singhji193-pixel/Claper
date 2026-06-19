defmodule Claper.EventAppAuthTest do
  use Claper.DataCase

  import Claper.{AgendasFixtures, EventsFixtures}

  alias Claper.EventApp
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

      assert Repo.aggregate(OtpChallenge, :count) == 0
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
      assert is_binary(token)

      assert Repo.get!(OtpChallenge, challenge.id).status == "verified"
      assert Repo.aggregate(Attendee, :count) == 1
      assert Repo.aggregate(Session, :count) == 1

      assert {:ok, bootstrap} = EventApp.bootstrap_event(event.code, token)
      assert bootstrap.attendee.authenticated
      assert bootstrap.attendee.email == "avery@example.com"
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
