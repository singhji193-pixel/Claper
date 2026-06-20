defmodule Claper.HiEvents.SyncTest do
  use Claper.DataCase

  import Claper.EventsFixtures

  alias Claper.HiEvents
  alias Claper.HiEvents.Sync

  test "imports existing orders and attendees and remains idempotent" do
    event = event_fixture()
    {:ok, integration} = HiEvents.upsert_integration(event.id, %{"external_event_id" => "3"})

    request = hi_events_request_fixture()
    options = sync_options(request)

    assert {:ok, result} = Sync.run(integration, options)
    assert result.orders == 1
    assert result.attendees == 2
    assert result.webhook == :created

    assert [order] = HiEvents.list_orders(event.id)
    assert order.external_order_id == "41"
    assert order.buyer_name == "Buyer One"

    tickets = HiEvents.list_tickets(event.id)
    assert length(tickets) == 2
    assert Enum.all?(tickets, &(&1.ticket_name == "General Admission"))
    assert Enum.any?(tickets, &(&1.checked_in_at != nil))

    integration = HiEvents.get_integration(event.id)
    assert integration.remote_webhook_id == "9"
    assert integration.webhook_secret == "native-webhook-secret-1234567890"
    assert integration.last_reconciled_at
    assert integration.last_reconcile_status == "ok"

    assert {:ok, repeated} = Sync.run(integration, options)
    assert repeated.duplicates == 3
    assert HiEvents.ticket_count(event.id) == 2
  end

  test "records a safe reconciliation failure" do
    event = event_fixture()
    {:ok, integration} = HiEvents.upsert_integration(event.id, %{"external_event_id" => "3"})

    request = fn _options -> {:ok, %Req.Response{status: 401, body: %{"password" => "leak"}}} end

    assert {:error, {:http_error, 401}} = Sync.run(integration, sync_options(request))

    integration = HiEvents.get_integration(event.id)
    assert integration.last_reconcile_status == "error"
    assert integration.last_error == "Hi.Events request failed (401)"
    refute integration.last_error =~ "leak"
  end

  defp sync_options(request) do
    [
      webhook_url: "https://ask.example/api/integrations/hi-events/webhook",
      client_options: [
        base_url: "https://events.example/api",
        email: "sync@example.com",
        password: "secret",
        request: request,
        per_page: 100
      ]
    ]
  end

  defp hi_events_request_fixture do
    fn options ->
      case {options[:method], options[:url]} do
        {:post, "https://events.example/api/auth/login"} ->
          {:ok, %Req.Response{status: 200, body: %{"token" => "token"}}}

        {:get, "https://events.example/api/events/3/webhooks"} ->
          {:ok, paginated([])}

        {:post, "https://events.example/api/events/3/webhooks"} ->
          assert options[:json]["status"] == "ENABLED"
          assert "order.created" in options[:json]["event_types"]

          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "data" => %{
                 "id" => 9,
                 "secret" => "native-webhook-secret-1234567890",
                 "url" => options[:json]["url"]
               }
             }
           }}

        {:get, "https://events.example/api/events/3/orders"} ->
          {:ok, paginated([order_payload()])}

        {:get, "https://events.example/api/events/3/attendees"} ->
          {:ok, paginated(attendee_payloads())}
      end
    end
  end

  defp paginated(data) do
    %Req.Response{
      status: 200,
      body: %{
        "data" => data,
        "meta" => %{"current_page" => 1, "last_page" => 1}
      }
    }
  end

  defp order_payload do
    %{
      "id" => 41,
      "event_id" => 3,
      "status" => "COMPLETED",
      "payment_status" => "PAYMENT_RECEIVED",
      "first_name" => "Buyer",
      "last_name" => "One",
      "email" => "buyer@example.com",
      "total_gross" => 12_500,
      "currency" => "CAD",
      "order_items" => [
        %{"product_id" => 6, "item_name" => "General Admission"}
      ],
      "attendees" => attendee_payloads()
    }
  end

  defp attendee_payloads do
    [
      %{
        "id" => 51,
        "public_id" => "attendee-public-51",
        "order_id" => 41,
        "event_id" => 3,
        "product_id" => 6,
        "status" => "ACTIVE",
        "email" => "avery@example.com",
        "first_name" => "Avery",
        "last_name" => "Singh",
        "check_ins" => [%{"created_at" => "2026-06-19T12:00:00+00:00"}]
      },
      %{
        "id" => 52,
        "public_id" => "attendee-public-52",
        "order_id" => 41,
        "event_id" => 3,
        "product_id" => 6,
        "status" => "ACTIVE",
        "email" => "sam@example.com",
        "first_name" => "Sam",
        "last_name" => "Lee",
        "check_ins" => []
      }
    ]
  end
end
