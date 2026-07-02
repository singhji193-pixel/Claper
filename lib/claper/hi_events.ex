defmodule Claper.HiEvents do
  @moduledoc """
  Hi.Events webhook sync for ticket, attendee, and check-in data.
  """

  import Ecto.Query, warn: false

  alias Claper.HiEvents.{EventTicket, Integration, Order, SyncEvent}
  alias Claper.Repo

  @signature_headers [
    "signature",
    "x-hi-events-signature",
    "x-hievents-signature",
    "x-webhook-signature",
    "x-signature",
    "x-hub-signature-256"
  ]

  @event_id_headers [
    "x-hi-events-event-id",
    "x-hievents-event-id",
    "x-event-id"
  ]

  @delivery_headers [
    "x-hi-events-delivery",
    "x-hievents-delivery",
    "x-webhook-id",
    "x-request-id"
  ]

  @sensitive_key_fragments [
    "card",
    "client_secret",
    "payment_method",
    "password",
    "secret",
    "stripe",
    "token"
  ]

  def generate_webhook_secret do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  def webhook_signature(secret, body) when is_binary(secret) and is_binary(body) do
    :crypto.mac(:hmac, :sha256, secret, body)
    |> Base.encode16(case: :lower)
  end

  def get_integration(event_id), do: Repo.get_by(Integration, event_id: event_id)

  def get_integration_by_external_event_id(external_event_id) when is_binary(external_event_id) do
    Repo.get_by(Integration, external_event_id: external_event_id)
  end

  def integration_for_event(event_id) do
    get_integration(event_id) ||
      %Integration{
        event_id: event_id,
        enabled: true,
        webhook_secret: generate_webhook_secret()
      }
  end

  def change_integration(%Integration{} = integration, attrs \\ %{}) do
    Integration.changeset(integration, attrs)
  end

  def upsert_integration(event_id, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("event_id", event_id)

    case get_integration(event_id) do
      nil ->
        attrs
        |> Map.put_new("webhook_secret", generate_webhook_secret())
        |> then(&Integration.changeset(%Integration{}, &1))
        |> Repo.insert()

      %Integration{} = integration ->
        attrs
        |> Map.put_new("webhook_secret", integration.webhook_secret)
        |> then(&Integration.changeset(integration, &1))
        |> Repo.update()
    end
  end

  def rotate_webhook_secret(%Integration{} = integration) do
    integration
    |> Integration.changeset(%{webhook_secret: generate_webhook_secret()})
    |> Repo.update()
  end

  def list_enabled_integrations do
    Integration
    |> where([i], i.enabled == true)
    |> order_by([i], asc: i.id)
    |> Repo.all()
  end

  def update_webhook_connection(%Integration{} = integration, remote_webhook_id, secret) do
    integration
    |> Integration.connection_changeset(%{
      remote_webhook_id: to_string(remote_webhook_id),
      webhook_secret: secret
    })
    |> Repo.update()
  end

  def record_reconcile_success(%Integration{} = integration) do
    integration
    |> Integration.status_changeset(%{
      last_reconciled_at: now(),
      last_reconcile_status: "ok",
      last_error: nil
    })
    |> Repo.update()
  end

  def record_reconcile_failure(%Integration{} = integration, message) do
    integration
    |> Integration.status_changeset(%{
      last_reconciled_at: now(),
      last_reconcile_status: "error",
      last_error: String.slice(to_string(message), 0, 1_000)
    })
    |> Repo.update()
  end

  def dashboard_stats(nil) do
    %{
      integration: nil,
      order_count: 0,
      ticket_count: 0,
      checked_in_count: 0,
      processed_count: 0,
      failed_count: 0,
      recent_events: []
    }
  end

  def dashboard_stats(event_id) do
    integration = get_integration(event_id)

    %{
      integration: integration,
      order_count: count_orders(event_id),
      ticket_count: ticket_count(event_id),
      checked_in_count: checked_in_count(event_id),
      processed_count: count_sync_events(event_id, "processed"),
      failed_count: count_sync_events(event_id, "failed"),
      recent_events: list_recent_sync_events(event_id)
    }
  end

  def list_recent_sync_events(event_id, limit \\ 8) do
    SyncEvent
    |> where([s], s.event_id == ^event_id)
    |> order_by([s], desc: s.received_at, desc: s.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_tickets(event_id) do
    EventTicket
    |> where([t], t.event_id == ^event_id)
    |> order_by([t], asc: t.attendee_name, asc: t.attendee_email)
    |> Repo.all()
  end

  def get_ticket_by_event_and_email(event_id, email) when is_binary(email) do
    normalized_email = normalize_email(email)

    EventTicket
    |> where([t], t.event_id == ^event_id)
    |> where([t], t.attendee_email == ^normalized_email)
    |> where([t], t.status not in ["cancelled", "canceled", "refunded", "void"])
    |> order_by([t], asc: t.id)
    |> limit(1)
    |> Repo.one()
  end

  def get_ticket_by_event_and_email(_event_id, _email), do: nil

  def list_orders(event_id) do
    Order
    |> where([o], o.event_id == ^event_id)
    |> order_by([o], desc: o.id)
    |> Repo.all()
  end

  def ticket_count(nil), do: 0

  def ticket_count(event_id) do
    EventTicket
    |> where([t], t.event_id == ^event_id)
    |> Repo.aggregate(:count)
  end

  def checked_in_count(nil), do: 0

  def checked_in_count(event_id) do
    EventTicket
    |> where(
      [t],
      t.event_id == ^event_id and (not is_nil(t.checked_in_at) or t.status == "checked_in")
    )
    |> Repo.aggregate(:count)
  end

  def count_orders(nil), do: 0

  def count_orders(event_id) do
    Order
    |> where([o], o.event_id == ^event_id)
    |> Repo.aggregate(:count)
  end

  def ingest_webhook(headers, raw_body, params \\ %{}) do
    headers = normalize_headers(headers)
    params = stringify_keys(params || %{})

    with {:ok, payload} <- decode_payload(raw_body, params),
         {:ok, external_event_id} <- external_event_id(headers, payload, params),
         {:ok, integration} <- integration_for_external_event(external_event_id),
         :ok <- verify_signature(integration, headers, raw_body || ""),
         event_type <- payload_event_type(payload),
         event_key <- delivery_key(headers, payload, raw_body || ""),
         {:ok, sync_event, duplicate?} <-
           insert_sync_event(integration, external_event_id, event_type, event_key, payload) do
      if duplicate? do
        {:ok, :duplicate, sync_event}
      else
        process_sync_event(sync_event)
      end
    end
  end

  def ingest_api_snapshot(%Integration{} = integration, event_type, payload)
      when is_binary(event_type) and is_map(payload) do
    envelope = %{
      "event_type" => event_type,
      "event_sent_at" => DateTime.to_iso8601(now()),
      "payload" => stringify_keys(payload)
    }

    encoded = Jason.encode!(envelope["payload"])
    source_id = payload["id"] || payload[:id] || "unknown"
    digest = :crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower)
    event_key = "api:#{event_type}:#{source_id}:#{digest}"

    with {:ok, sync_event, duplicate?} <-
           insert_sync_event(
             integration,
             integration.external_event_id,
             event_type,
             event_key,
             envelope
           ) do
      if duplicate? do
        {:ok, :duplicate, sync_event}
      else
        process_sync_event(sync_event)
      end
    end
  end

  def process_sync_event(%SyncEvent{} = sync_event) do
    sync_event = Repo.preload(sync_event, :integration)

    Repo.transaction(fn ->
      normalized = normalize_payload(sync_event.payload, sync_event.external_event_id)
      processed_at = now()

      with {:ok, order} <- upsert_order(sync_event, normalized.order),
           :ok <- upsert_tickets(sync_event, order, normalized.attendees),
           {:ok, sync_event} <-
             sync_event
             |> SyncEvent.status_changeset(%{status: "processed", processed_at: processed_at})
             |> Repo.update(),
           {:ok, _integration} <-
             sync_event.integration
             |> Integration.status_changeset(%{
               last_event_key: sync_event.external_event_key,
               last_event_type: sync_event.external_event_type,
               last_received_at: sync_event.received_at,
               last_error: nil
             })
             |> Repo.update() do
        sync_event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, sync_event} ->
        {:ok, :processed, sync_event}

      {:error, reason} ->
        mark_sync_event_failed(sync_event, inspect(reason))
        {:error, {:processing_failed, reason}}
    end
  rescue
    error ->
      mark_sync_event_failed(sync_event, Exception.message(error))
      {:error, {:processing_failed, error}}
  end

  defp insert_sync_event(integration, external_event_id, event_type, event_key, payload) do
    attrs = %{
      event_id: integration.event_id,
      integration_id: integration.id,
      external_event_id: external_event_id,
      external_event_type: event_type || "unknown",
      external_event_key: event_key,
      payload: sanitize_payload(payload),
      status: "received",
      received_at: now()
    }

    changeset = SyncEvent.changeset(%SyncEvent{}, attrs)

    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:integration_id, :external_event_key]
         ) do
      {:ok, %SyncEvent{id: nil}} ->
        sync_event =
          Repo.get_by!(SyncEvent,
            integration_id: integration.id,
            external_event_key: event_key
          )

        {:ok, sync_event, true}

      {:ok, sync_event} ->
        {:ok, sync_event, false}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp upsert_order(_sync_event, nil), do: {:ok, nil}

  defp upsert_order(%SyncEvent{} = sync_event, attrs) do
    attrs =
      attrs
      |> Map.put(:event_id, sync_event.event_id)
      |> Map.put(:integration_id, sync_event.integration_id)

    %Order{}
    |> Order.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :status,
           :buyer_name,
           :buyer_email,
           :total_cents,
           :currency,
           :raw_payload,
           :updated_at
         ]},
      conflict_target: [:integration_id, :external_order_id],
      returning: true
    )
    |> case do
      {:ok, order} -> {:ok, order}
      {:error, changeset} -> {:error, {:invalid_order, changeset}}
    end
  end

  defp upsert_tickets(sync_event, order, attendees) do
    Enum.reduce_while(attendees, :ok, fn attendee, :ok ->
      case upsert_ticket(sync_event, order, attendee) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upsert_ticket(_sync_event, _order, nil), do: :ok

  defp upsert_ticket(%SyncEvent{} = sync_event, order, attrs) do
    identity =
      attrs[:external_attendee_id] || attrs[:external_ticket_id] || attrs[:attendee_email]

    if blank?(identity) do
      :ok
    else
      attrs =
        attrs
        |> Map.put(:event_id, sync_event.event_id)
        |> Map.put(:integration_id, sync_event.integration_id)
        |> Map.put(:external_attendee_id, attrs[:external_attendee_id] || identity)
        |> Map.put(:hi_events_order_id, order && order.id)

      %EventTicket{}
      |> EventTicket.changeset(attrs)
      |> Repo.insert(
        on_conflict:
          {:replace,
           [
             :hi_events_order_id,
             :external_ticket_id,
             :external_ticket_type_id,
             :external_public_id,
             :ticket_name,
             :attendee_email,
             :attendee_first_name,
             :attendee_last_name,
             :attendee_name,
             :status,
             :checked_in_at,
             :raw_payload,
             :updated_at
           ]},
        conflict_target: [:integration_id, :external_attendee_id],
        returning: true
      )
      |> case do
        {:ok, _ticket} -> :ok
        {:error, changeset} -> {:error, {:invalid_ticket, changeset}}
      end
    end
  end

  defp mark_sync_event_failed(sync_event, error) do
    processed_at = now()

    sync_event
    |> SyncEvent.status_changeset(%{
      status: "failed",
      error: String.slice(to_string(error), 0, 1_000),
      processed_at: processed_at
    })
    |> Repo.update()

    sync_event = Repo.preload(sync_event, :integration)

    sync_event.integration
    |> Integration.status_changeset(%{
      last_event_key: sync_event.external_event_key,
      last_event_type: sync_event.external_event_type,
      last_received_at: sync_event.received_at,
      last_error: String.slice(to_string(error), 0, 1_000)
    })
    |> Repo.update()
  end

  defp normalize_payload(payload, external_event_id) do
    event_type = payload_event_type(payload)
    order_map = order_payload(payload)
    order = normalize_order(order_map, payload, event_type)

    attendees =
      payload
      |> attendee_payloads()
      |> Enum.map(&normalize_attendee(&1, event_type, external_event_id))
      |> Enum.reject(&is_nil/1)

    %{event_type: event_type, order: order, attendees: attendees}
  end

  defp normalize_order(nil, _payload, _event_type), do: nil

  defp normalize_order(order_map, payload, event_type) do
    external_order_id =
      first_value(order_map, [
        ["id"],
        ["order_id"],
        ["uuid"],
        ["public_id"],
        ["reference"]
      ]) ||
        first_value(payload, [
          ["order_id"],
          ["data", "order_id"],
          ["data", "order", "id"]
        ])

    if blank?(external_order_id) do
      nil
    else
      %{
        external_order_id: to_string_value(external_order_id),
        status: status_for(event_type, order_map),
        buyer_name:
          first_value(order_map, [
            ["customer", "name"],
            ["buyer", "name"],
            ["customer_name"],
            ["buyer_name"],
            ["name"]
          ]) ||
            join_name(get_path(order_map, ["first_name"]), get_path(order_map, ["last_name"])),
        buyer_email:
          first_value(order_map, [
            ["customer", "email"],
            ["buyer", "email"],
            ["customer_email"],
            ["buyer_email"],
            ["email"]
          ]),
        total_cents:
          first_value(order_map, [
            ["total_cents"],
            ["total_gross"],
            ["total"],
            ["amount_total"],
            ["amount"]
          ])
          |> to_integer(),
        currency:
          first_value(order_map, [["currency"], ["currency_code"]])
          |> uppercase_string(),
        raw_payload: order_map
      }
    end
  end

  defp normalize_attendee(attendee, event_type, external_event_id) when is_map(attendee) do
    ticket = first_map(attendee, [["ticket"], ["ticket_type"], ["product"]]) || %{}

    email =
      first_value(attendee, [
        ["email"],
        ["attendee_email"],
        ["user", "email"],
        ["customer", "email"]
      ])

    first_name =
      first_value(attendee, [
        ["first_name"],
        ["firstName"],
        ["attendee_first_name"],
        ["name", "first"]
      ])

    last_name =
      first_value(attendee, [
        ["last_name"],
        ["lastName"],
        ["attendee_last_name"],
        ["name", "last"]
      ])

    name =
      first_value(attendee, [
        ["name"],
        ["full_name"],
        ["attendee_name"],
        ["customer", "name"]
      ]) || join_name(first_name, last_name)

    external_attendee_id =
      first_value(attendee, [["id"], ["attendee_id"], ["uuid"], ["public_id"]])

    external_ticket_id =
      first_value(attendee, [
        ["ticket_id"],
        ["ticket", "id"],
        ["ticket", "uuid"],
        ["public_id"],
        ["short_id"]
      ]) || first_value(ticket, [["id"], ["uuid"]])

    %{
      external_attendee_id: to_string_value(external_attendee_id),
      external_ticket_id: to_string_value(external_ticket_id),
      external_public_id: to_string_value(first_value(attendee, [["public_id"]])),
      external_ticket_type_id:
        first_value(attendee, [
          ["ticket_type_id"],
          ["product_id"],
          ["ticket", "ticket_type_id"],
          ["ticket", "product_id"]
        ])
        |> to_string_value(),
      ticket_name:
        first_value(attendee, [
          ["ticket_name"],
          ["product_name"],
          ["ticket", "name"],
          ["ticket", "title"],
          ["ticket_type", "name"],
          ["product", "title"]
        ]) || first_value(ticket, [["name"], ["title"]]),
      attendee_email: to_string_value(email),
      attendee_first_name: to_string_value(first_name),
      attendee_last_name: to_string_value(last_name),
      attendee_name: to_string_value(name),
      status: status_for(event_type, attendee),
      checked_in_at: checked_in_at(event_type, attendee),
      raw_payload: Map.put_new(attendee, "external_event_id", external_event_id)
    }
  end

  defp normalize_attendee(_attendee, _event_type, _external_event_id), do: nil

  defp order_payload(payload) do
    first_map(payload, [
      ["data", "order"],
      ["order"],
      ["payload", "order"],
      ["data", "payload", "order"]
    ]) || native_payload_as_order(payload) || data_as_order(payload)
  end

  defp native_payload_as_order(payload) do
    native_payload = get_path(payload, ["payload"])
    event_type = payload_event_type(payload) |> String.downcase()

    if is_map(native_payload) and String.starts_with?(event_type, "order.") do
      native_payload
    end
  end

  defp data_as_order(payload) do
    data = get_path(payload, ["data"])

    if is_map(data) and
         (present?(get_path(data, ["order_id"])) or present?(get_path(data, ["customer_email"]))) do
      data
    end
  end

  defp attendee_payloads(payload) do
    nested =
      [
        ["data", "order", "attendees"],
        ["order", "attendees"],
        ["data", "attendees"],
        ["attendees"],
        ["data", "attendee"],
        ["attendee"],
        ["payload", "attendees"],
        ["payload", "attendee"],
        ["data", "payload", "attendees"]
      ]
      |> Enum.flat_map(fn path ->
        payload
        |> get_path(path)
        |> listify_payload()
      end)

    native_payload = get_path(payload, ["payload"])
    event_type = payload_event_type(payload) |> String.downcase()

    if is_map(native_payload) and String.starts_with?(event_type, "attendee.") do
      [native_payload | nested]
    else
      nested
    end
  end

  defp listify_payload(nil), do: []
  defp listify_payload(value) when is_list(value), do: Enum.filter(value, &is_map/1)
  defp listify_payload(value) when is_map(value), do: [value]
  defp listify_payload(_value), do: []

  defp payload_event_type(payload) do
    first_value(payload, [
      ["type"],
      ["event"],
      ["event_type"],
      ["eventType"],
      ["name"],
      ["data", "type"],
      ["data", "event_type"]
    ])
    |> to_string_value()
    |> case do
      nil -> "unknown"
      value -> value
    end
  end

  defp status_for(event_type, payload) do
    event_type = event_type |> to_string_value() |> String.downcase()

    status =
      first_value(payload || %{}, [
        ["status"],
        ["state"],
        ["ticket_status"],
        ["attendee_status"]
      ])
      |> to_string_value()
      |> normalize_status()

    status = if present?(status), do: status

    status_from_event_type(event_type) || status || "active"
  end

  defp status_from_event_type(event_type) do
    cond do
      String.contains?(event_type, "cancel") -> "cancelled"
      String.contains?(event_type, "refund") -> "cancelled"
      String.contains?(event_type, "checkin.deleted") -> nil
      String.contains?(event_type, "check") and String.contains?(event_type, "in") -> "checked_in"
      true -> nil
    end
  end

  defp normalize_status(nil), do: nil

  defp normalize_status(status) do
    case status |> to_string_value() |> String.downcase() do
      value when value in ["complete", "completed", "confirmed", "paid", "success"] -> "active"
      value when value in ["checked_in", "checked-in", "checked in"] -> "checked_in"
      value when value in ["cancelled", "canceled", "refunded", "void"] -> "cancelled"
      value when value in ["pending", "failed"] -> value
      value -> value
    end
  end

  defp checked_in_at(event_type, attendee) do
    checked_at =
      first_value(attendee, [
        ["checked_in_at"],
        ["checkedInAt"],
        ["check_in_at"],
        ["checkin_at"]
      ]) || first_check_in_time(attendee)

    normalized_event_type = event_type |> to_string_value() |> String.downcase()

    cond do
      String.contains?(normalized_event_type, "checkin.deleted") -> nil
      present?(checked_at) -> parse_datetime(checked_at)
      status_for(event_type, attendee) == "checked_in" -> now()
      true -> nil
    end
  end

  defp first_check_in_time(attendee) do
    attendee
    |> Map.get("check_ins", [])
    |> List.wrap()
    |> Enum.find_value(fn
      check_in when is_map(check_in) ->
        first_value(check_in, [["created_at"], ["checked_in_at"], ["check_in_at"]])

      _other ->
        nil
    end)
  end

  defp parse_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
  defp parse_datetime(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp decode_payload(raw_body, params) when is_binary(raw_body) and raw_body != "" do
    case Jason.decode(raw_body) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, _payload} -> {:error, :invalid_payload}
      {:error, _error} when map_size(params) > 0 -> {:ok, params}
      {:error, _error} -> {:error, :invalid_json}
    end
  end

  defp decode_payload(_raw_body, params) when is_map(params) and map_size(params) > 0 do
    {:ok, params}
  end

  defp decode_payload(_raw_body, _params), do: {:error, :invalid_payload}

  defp external_event_id(headers, payload, params) do
    value =
      header_value(headers, @event_id_headers) ||
        first_value(params, [["external_event_id"], ["event_id"]]) ||
        first_value(payload, [
          ["external_event_id"],
          ["event_id"],
          ["event", "id"],
          ["payload", "event_id"],
          ["data", "external_event_id"],
          ["data", "event_id"],
          ["data", "event", "id"]
        ])

    if blank?(value), do: {:error, :missing_event_id}, else: {:ok, to_string_value(value)}
  end

  defp integration_for_external_event(external_event_id) do
    case get_integration_by_external_event_id(external_event_id) do
      %Integration{enabled: true} = integration -> {:ok, integration}
      %Integration{} -> {:error, :disabled}
      nil -> {:error, :unknown_event}
    end
  end

  defp verify_signature(integration, headers, raw_body) do
    signature = header_value(headers, @signature_headers)

    cond do
      blank?(signature) ->
        {:error, :missing_signature}

      valid_signature?(integration.webhook_secret, raw_body, signature) ->
        :ok

      true ->
        {:error, :invalid_signature}
    end
  end

  defp valid_signature?(secret, body, signature) do
    expected = webhook_signature(secret, body)
    actual = normalize_signature(signature)

    byte_size(expected) == byte_size(actual) and Plug.Crypto.secure_compare(expected, actual)
  end

  defp normalize_signature(signature) do
    signature
    |> to_string_value()
    |> String.trim()
    |> String.split(",", parts: 2)
    |> List.first()
    |> String.replace_prefix("sha256=", "")
    |> String.downcase()
  end

  defp delivery_key(headers, payload, raw_body) do
    payload_key =
      first_value(payload, [["id"], ["webhook_id"], ["delivery_id"], ["data", "id"]])

    header_value(headers, @delivery_headers) ||
      case payload_key do
        nil -> :crypto.hash(:sha256, raw_body) |> Base.encode16(case: :lower)
        value -> to_string_value(value)
      end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Map.new(headers, fn {key, value} ->
      {key |> to_string() |> String.downcase(), to_string_value(value)}
    end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {key, value} ->
      {key |> to_string() |> String.downcase(), to_string_value(value)}
    end)
  end

  defp normalize_headers(_headers), do: %{}

  defp header_value(headers, names) do
    Enum.find_value(names, &Map.get(headers, &1))
  end

  defp sanitize_payload(payload) when is_map(payload) do
    Map.new(payload, fn {key, value} ->
      key_string = to_string(key)

      if sensitive_key?(key_string) do
        {key_string, "[FILTERED]"}
      else
        {key_string, sanitize_payload(value)}
      end
    end)
  end

  defp sanitize_payload(payload) when is_list(payload), do: Enum.map(payload, &sanitize_payload/1)
  defp sanitize_payload(payload), do: payload

  defp sensitive_key?(key) do
    normalized = String.downcase(key)
    Enum.any?(@sensitive_key_fragments, &String.contains?(normalized, &1))
  end

  defp first_map(map, paths) do
    Enum.find_value(paths, fn path ->
      case get_path(map, path) do
        value when is_map(value) -> value
        _ -> nil
      end
    end)
  end

  defp first_value(map, paths) do
    Enum.find_value(paths, fn path ->
      case get_path(map, path) do
        value when value in [nil, ""] -> nil
        value -> value
      end
    end)
  end

  defp get_path(map, path) when is_map(map) do
    Enum.reduce_while(path, map, fn key, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, key) ->
          {:cont, Map.get(acc, key)}

        is_map(acc) and existing_atom_key?(acc, key) ->
          {:cont, Map.get(acc, String.to_existing_atom(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp get_path(_map, _path), do: nil

  defp existing_atom_key?(map, key) do
    atom = String.to_existing_atom(key)
    Map.has_key?(map, atom)
  rescue
    ArgumentError -> false
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      value =
        if is_map(value) do
          stringify_keys(value)
        else
          value
        end

      {to_string(key), value}
    end)
  end

  defp stringify_keys(value), do: value

  defp to_string_value(nil), do: nil
  defp to_string_value(value) when is_binary(value), do: String.trim(value)
  defp to_string_value(value), do: value |> to_string() |> String.trim()

  defp normalize_email(email) do
    email
    |> to_string_value()
    |> String.downcase()
  end

  defp uppercase_string(nil), do: nil
  defp uppercase_string(value), do: value |> to_string_value() |> String.upcase()

  defp to_integer(nil), do: nil
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_float(value), do: round(value)

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> nil
    end
  end

  defp to_integer(_value), do: nil

  defp join_name(nil, nil), do: nil
  defp join_name(first_name, nil), do: first_name
  defp join_name(nil, last_name), do: last_name
  defp join_name(first_name, last_name), do: "#{first_name} #{last_name}"

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp present?(value), do: not blank?(value)

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp count_sync_events(nil, _status), do: 0

  defp count_sync_events(event_id, status) do
    SyncEvent
    |> where([s], s.event_id == ^event_id and s.status == ^status)
    |> Repo.aggregate(:count)
  end
end
