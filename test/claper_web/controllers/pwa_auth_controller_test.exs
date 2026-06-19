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

      assert html_response(conn, 200) =~ "Enter the email on your ticket"
      assert html_response(conn, 200) =~ event.name
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

    test "sets attendee session after code verification", %{conn: conn} do
      event = event_fixture()
      ticket_fixture(event, %{attendee_email: "avery@example.com"})

      assert {:ok, _result} =
               EventApp.request_login_code(event.code, "avery@example.com", code: "4821")

      conn =
        post(conn, ~p"/app/#{event.code}/verify", %{
          "attendee" => %{"email" => "avery@example.com", "code" => "4821"}
        })

      assert redirected_to(conn) == ~p"/app/#{event.code}/profile"
      assert get_session(conn, :event_app_session_token)
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
end
