defmodule ClaperWeb.PwaAuthControllerTest do
  use ClaperWeb.ConnCase

  import Claper.EventsFixtures

  alias Claper.EventApp
  alias Claper.HiEvents
  alias Claper.HiEvents.EventTicket
  alias Claper.Repo

  describe "attendee login" do
    test "renders the ticket email login screen", %{conn: conn} do
      event = event_fixture()

      conn = get(conn, ~p"/app/#{event.code}/login")

      assert html_response(conn, 200) =~ "Sign in with your ticket"
      assert html_response(conn, 200) =~ "ngs-auth-shell-reference"
      assert html_response(conn, 200) =~ "/images/logo-large.png"
    end

    test "renders the vanity host login screen without the event code path", %{conn: conn} do
      event = event_fixture()
      put_public_event_code(event.code)

      conn =
        conn
        |> Map.put(:host, "app.nextgensummit.co")
        |> get("/login")

      html = html_response(conn, 200)

      assert html =~ "Sign in with your ticket"
      assert html =~ "ngs-auth-shell-reference"
      assert html =~ "/images/logo-large.png"
      assert html =~ ~s(action="/login")
      refute html =~ "/app/#{event.code}/login"
    end

    test "requests a code for a synced ticket and redirects to verify", %{conn: conn} do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      conn =
        post(conn, ~p"/app/#{event.code}/login", %{
          "attendee" => %{"email" => "avery@example.com"}
        })

      assert redirected_to(conn) == ~p"/app/#{event.code}/verify?#{[email: "avery@example.com"]}"
    end

    test "preserves a safe return path through coded OTP request", %{conn: conn} do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      conn =
        post(conn, ~p"/app/#{event.code}/login", %{
          "attendee" => %{
            "email" => "avery@example.com",
            "next" => ~p"/app/#{event.code}/agenda"
          }
        })

      assert_verify_redirect(conn, ~p"/app/#{event.code}/verify", %{
        "email" => "avery@example.com",
        "next" => ~p"/app/#{event.code}/agenda"
      })
    end

    test "requests a code from the vanity host and redirects to vanity verify", %{conn: conn} do
      event = event_fixture()
      put_public_event_code(event.code)
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      conn =
        conn
        |> Map.put(:host, "app.nextgensummit.co")
        |> post("/login", %{
          "attendee" => %{"email" => "avery@example.com"}
        })

      assert redirected_to(conn) == "/verify?email=avery%40example.com"
    end

    test "sets attendee session after code verification", %{conn: conn} do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      conn =
        post(conn, ~p"/app/#{event.code}/verify", %{
          "attendee" => %{"email" => "avery@example.com", "code" => "4821"}
        })

      assert redirected_to(conn) == ~p"/app/#{event.code}"
      assert get_session(conn, :event_app_session_token)
    end

    test "sets attendee session and returns to vanity next path after verification", %{conn: conn} do
      event = event_fixture()
      put_public_event_code(event.code)
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      conn =
        conn
        |> Map.put(:host, "app.nextgensummit.co")
        |> post("/verify", %{
          "attendee" => %{
            "email" => "avery@example.com",
            "code" => "4821",
            "next" => "/agenda"
          }
        })

      assert redirected_to(conn) == "/agenda"
      assert get_session(conn, :event_app_session_token)
    end

    test "rejects unsafe vanity next paths after verification", %{conn: conn} do
      event = event_fixture()
      put_public_event_code(event.code)
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      conn =
        conn
        |> Map.put(:host, "app.nextgensummit.co")
        |> post("/verify", %{
          "attendee" => %{
            "email" => "avery@example.com",
            "code" => "4821",
            "next" => "https://evil.example.com"
          }
        })

      assert redirected_to(conn) == "/"
    end

    test "shows an inline error when no ticket is found", %{conn: conn} do
      event = event_fixture()

      conn =
        post(conn, ~p"/app/#{event.code}/login", %{
          "attendee" => %{"email" => "missing@example.com"}
        })

      assert html_response(conn, 200) =~ "No active ticket was found"
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

  defp assert_verify_redirect(conn, expected_path, expected_params) do
    redirected = redirected_to(conn)
    uri = URI.parse(redirected)

    assert uri.path == expected_path
    assert Plug.Conn.Query.decode(uri.query || "") == expected_params
  end
end
