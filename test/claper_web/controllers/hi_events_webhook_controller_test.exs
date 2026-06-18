defmodule ClaperWeb.HiEventsWebhookControllerTest do
  use ClaperWeb.ConnCase

  import Claper.EventsFixtures

  alias Claper.HiEvents

  describe "POST /api/integrations/hi-events/webhook" do
    test "accepts a signed Hi.Events webhook", %{conn: conn} do
      event = event_fixture()
      integration = integration_fixture(event)
      body = Jason.encode!(payload("controller-delivery", integration.external_event_id))

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hi-events-event-id", integration.external_event_id)
        |> put_req_header(
          "x-hi-events-signature",
          "sha256=#{HiEvents.webhook_signature(integration.webhook_secret, body)}"
        )
        |> post(~p"/api/integrations/hi-events/webhook", body)

      assert %{"data" => %{"status" => "processed"}} = json_response(conn, 202)
      assert HiEvents.ticket_count(event.id) == 1
    end

    test "rejects bad signatures", %{conn: conn} do
      event = event_fixture()
      integration = integration_fixture(event)
      body = Jason.encode!(payload("bad-signature", integration.external_event_id))

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hi-events-event-id", integration.external_event_id)
        |> put_req_header("x-hi-events-signature", "sha256=bad")
        |> post(~p"/api/integrations/hi-events/webhook", body)

      assert %{"error" => "invalid_signature"} = json_response(conn, 401)
      assert HiEvents.ticket_count(event.id) == 0
    end

    test "returns not found for unknown external event ids", %{conn: conn} do
      body = Jason.encode!(payload("unknown-event", "missing-event"))

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hi-events-event-id", "missing-event")
        |> put_req_header("x-hi-events-signature", "sha256=anything")
        |> post(~p"/api/integrations/hi-events/webhook", body)

      assert %{"error" => "unknown_hi_events_event"} = json_response(conn, 404)
    end
  end

  defp integration_fixture(event) do
    {:ok, integration} =
      HiEvents.upsert_integration(event.id, %{"external_event_id" => "hi_evt_#{event.id}"})

    integration
  end

  defp payload(delivery_id, external_event_id) do
    %{
      "id" => delivery_id,
      "type" => "order.completed",
      "event_id" => external_event_id,
      "data" => %{
        "order" => %{
          "id" => "order_#{delivery_id}",
          "customer" => %{"email" => "buyer@example.com"},
          "attendees" => [
            %{
              "id" => "attendee_#{delivery_id}",
              "email" => "attendee@example.com",
              "name" => "Avery Singh",
              "ticket" => %{"id" => "ticket_#{delivery_id}", "name" => "General"}
            }
          ]
        }
      }
    }
  end
end
