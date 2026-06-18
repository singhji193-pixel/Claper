defmodule Claper.HiEventsTest do
  use Claper.DataCase

  import Claper.EventsFixtures

  alias Claper.HiEvents
  alias Claper.HiEvents.SyncEvent

  describe "integrations" do
    test "creates an event integration with a generated signing secret" do
      event = event_fixture()

      assert {:ok, integration} =
               HiEvents.upsert_integration(event.id, %{"external_event_id" => "hi_evt_123"})

      assert integration.event_id == event.id
      assert integration.external_event_id == "hi_evt_123"
      assert integration.enabled
      assert byte_size(integration.webhook_secret) >= 24
    end

    test "validates the external event id" do
      event = event_fixture()

      assert {:error, changeset} =
               HiEvents.upsert_integration(event.id, %{"external_event_id" => ""})

      assert "can't be blank" in errors_on(changeset).external_event_id
    end
  end

  describe "webhook ingestion" do
    test "verifies the signature and creates order, ticket, and delivery rows" do
      event = event_fixture()
      integration = integration_fixture(event)
      body = Jason.encode!(order_payload("delivery-1", integration.external_event_id))

      assert {:ok, :processed, sync_event} =
               HiEvents.ingest_webhook(signed_headers(integration, body), body)

      assert sync_event.status == "processed"

      assert [order] = HiEvents.list_orders(event.id)
      assert order.external_order_id == "ord_1"
      assert order.buyer_email == "buyer@example.com"
      assert order.total_cents == 12_500
      assert order.raw_payload["payment_method"] == "[FILTERED]"

      assert [ticket] = HiEvents.list_tickets(event.id)
      assert ticket.external_attendee_id == "att_1"
      assert ticket.external_ticket_id == "ticket_1"
      assert ticket.ticket_name == "Builder Pass"
      assert ticket.attendee_name == "Avery Singh"
      assert ticket.status == "active"

      assert [%SyncEvent{} = delivery] = Repo.all(SyncEvent)
      assert delivery.payload["data"]["order"]["payment_method"] == "[FILTERED]"
      assert delivery.payload["data"]["order"]["secret_note"] == "[FILTERED]"
    end

    test "ignores duplicate delivery ids" do
      event = event_fixture()
      integration = integration_fixture(event)
      body = Jason.encode!(order_payload("delivery-duplicate", integration.external_event_id))

      assert {:ok, :processed, _sync_event} =
               HiEvents.ingest_webhook(signed_headers(integration, body), body)

      assert {:ok, :duplicate, _sync_event} =
               HiEvents.ingest_webhook(signed_headers(integration, body), body)

      assert Repo.aggregate(SyncEvent, :count) == 1
      assert length(HiEvents.list_tickets(event.id)) == 1
    end

    test "rejects invalid signatures before storing data" do
      event = event_fixture()
      integration = integration_fixture(event)
      body = Jason.encode!(order_payload("delivery-invalid", integration.external_event_id))

      assert {:error, :invalid_signature} =
               HiEvents.ingest_webhook(
                 [{"x-hi-events-signature", "sha256=bad"}],
                 body
               )

      assert Repo.aggregate(SyncEvent, :count) == 0
      assert HiEvents.ticket_count(event.id) == 0
    end

    test "updates check-in and cancellation status for an existing attendee" do
      event = event_fixture()
      integration = integration_fixture(event)
      order_body = Jason.encode!(order_payload("delivery-order", integration.external_event_id))

      assert {:ok, :processed, _sync_event} =
               HiEvents.ingest_webhook(signed_headers(integration, order_body), order_body)

      check_in_body =
        Jason.encode!(%{
          "id" => "delivery-check-in",
          "type" => "attendee.checked_in",
          "event_id" => integration.external_event_id,
          "data" => %{
            "attendee" => %{
              "id" => "att_1",
              "email" => "avery@example.com",
              "first_name" => "Avery",
              "last_name" => "Singh",
              "ticket" => %{"id" => "ticket_1", "name" => "Builder Pass"}
            }
          }
        })

      assert {:ok, :processed, _sync_event} =
               HiEvents.ingest_webhook(signed_headers(integration, check_in_body), check_in_body)

      assert [checked_in] = HiEvents.list_tickets(event.id)
      assert checked_in.status == "checked_in"
      assert checked_in.checked_in_at

      cancel_body =
        Jason.encode!(%{
          "id" => "delivery-cancel",
          "type" => "ticket.cancelled",
          "event_id" => integration.external_event_id,
          "data" => %{
            "attendee" => %{
              "id" => "att_1",
              "email" => "avery@example.com",
              "ticket" => %{"id" => "ticket_1", "name" => "Builder Pass"}
            }
          }
        })

      assert {:ok, :processed, _sync_event} =
               HiEvents.ingest_webhook(signed_headers(integration, cancel_body), cancel_body)

      assert [cancelled] = HiEvents.list_tickets(event.id)
      assert cancelled.status == "cancelled"
    end
  end

  defp integration_fixture(event) do
    {:ok, integration} =
      HiEvents.upsert_integration(event.id, %{"external_event_id" => "hi_evt_#{event.id}"})

    integration
  end

  defp signed_headers(integration, body) do
    [
      {"x-hi-events-event-id", integration.external_event_id},
      {"x-hi-events-signature",
       "sha256=#{HiEvents.webhook_signature(integration.webhook_secret, body)}"}
    ]
  end

  defp order_payload(delivery_id, external_event_id) do
    %{
      "id" => delivery_id,
      "type" => "order.completed",
      "event_id" => external_event_id,
      "data" => %{
        "order" => %{
          "id" => "ord_1",
          "customer" => %{"name" => "Buyer One", "email" => "buyer@example.com"},
          "currency" => "usd",
          "total_cents" => 12_500,
          "payment_method" => %{"card" => "4242424242424242"},
          "secret_note" => "do-not-store",
          "attendees" => [
            %{
              "id" => "att_1",
              "email" => "avery@example.com",
              "first_name" => "Avery",
              "last_name" => "Singh",
              "ticket" => %{"id" => "ticket_1", "name" => "Builder Pass"}
            }
          ]
        }
      }
    }
  end
end
