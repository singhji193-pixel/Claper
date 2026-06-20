defmodule Claper.HiEvents.Sync do
  @moduledoc """
  Reconciles the Hi.Events organizer API into Claper's local ticket read model.
  """

  alias Claper.HiEvents
  alias Claper.HiEvents.{Client, Integration}

  @webhook_event_types ~w(
    order.created
    order.updated
    order.marked_as_paid
    order.refunded
    order.cancelled
    attendee.created
    attendee.updated
    attendee.cancelled
    checkin.created
    checkin.deleted
  )

  def run(%Integration{} = integration, options \\ []) do
    client_options = Keyword.get(options, :client_options, [])
    webhook_url = Keyword.get(options, :webhook_url) || configured_webhook_url()

    result =
      with {:ok, webhook_url} <- validate_webhook_url(webhook_url),
           {:ok, token} <- Client.login(client_options),
           {:ok, webhook_status} <-
             ensure_webhook(integration, token, webhook_url, client_options),
           {:ok, orders} <-
             Client.list_orders(integration.external_event_id, token, client_options),
           {:ok, attendees} <-
             Client.list_attendees(integration.external_event_id, token, client_options),
           {:ok, import_result} <- import_snapshots(integration, orders, attendees) do
        {:ok, Map.put(import_result, :webhook, webhook_status)}
      end

    case result do
      {:ok, details} ->
        HiEvents.record_reconcile_success(integration)
        {:ok, details}

      {:error, reason} ->
        HiEvents.record_reconcile_failure(integration, error_message(reason))
        {:error, reason}
    end
  end

  def error_message({:http_error, status}) when is_integer(status),
    do: "Hi.Events request failed (#{status})"

  def error_message(:not_configured), do: "Hi.Events sync credentials are not configured"
  def error_message(:transport_error), do: "Hi.Events could not be reached"
  def error_message(:invalid_response), do: "Hi.Events returned an invalid response"
  def error_message(:page_limit_exceeded), do: "Hi.Events pagination limit was exceeded"
  def error_message(:invalid_webhook_url), do: "The Claper webhook URL is invalid"

  def error_message(:unmanaged_webhook_exists),
    do: "An unmanaged Hi.Events webhook already exists"

  def error_message(_reason), do: "Hi.Events synchronization failed"

  defp ensure_webhook(integration, token, webhook_url, client_options) do
    attrs = %{
      "url" => webhook_url,
      "event_types" => @webhook_event_types,
      "status" => "ENABLED"
    }

    with {:ok, webhooks} <-
           Client.list_webhooks(integration.external_event_id, token, client_options) do
      matching_url = Enum.find(webhooks, &(&1["url"] == webhook_url))
      matching_id = Enum.find(webhooks, &(to_string(&1["id"]) == integration.remote_webhook_id))

      cond do
        matching_url && is_nil(integration.remote_webhook_id) ->
          {:error, :unmanaged_webhook_exists}

        matching_url &&
          to_string(matching_url["id"]) == integration.remote_webhook_id &&
            webhook_current?(matching_url) ->
          {:ok, :unchanged}

        matching_id ->
          update_webhook(integration, matching_id, token, attrs, client_options)

        matching_url ->
          {:error, :unmanaged_webhook_exists}

        true ->
          create_webhook(integration, token, attrs, client_options)
      end
    end
  end

  defp create_webhook(integration, token, attrs, client_options) do
    with {:ok, webhook} <-
           Client.create_webhook(
             integration.external_event_id,
             token,
             attrs,
             client_options
           ),
         {:ok, _integration} <-
           HiEvents.update_webhook_connection(
             integration,
             webhook["id"],
             webhook["secret"]
           ) do
      {:ok, :created}
    end
  end

  defp update_webhook(integration, webhook, token, attrs, client_options) do
    with {:ok, _webhook} <-
           Client.update_webhook(
             integration.external_event_id,
             webhook["id"],
             token,
             attrs,
             client_options
           ),
         {:ok, _integration} <-
           HiEvents.update_webhook_connection(
             integration,
             webhook["id"],
             integration.webhook_secret
           ) do
      {:ok, :updated}
    end
  end

  defp webhook_current?(webhook) do
    webhook["status"] == "ENABLED" &&
      MapSet.new(webhook["event_types"] || []) == MapSet.new(@webhook_event_types)
  end

  defp import_snapshots(integration, orders, attendees) do
    product_names = product_names(orders)
    orders_by_id = Map.new(orders, &{to_string(&1["id"]), &1})

    order_results =
      Enum.map(orders, fn order ->
        order
        |> enrich_order(product_names)
        |> then(&HiEvents.ingest_api_snapshot(integration, "order.updated", &1))
      end)

    attendee_results =
      Enum.map(attendees, fn attendee ->
        attendee
        |> enrich_attendee(product_names)
        |> attach_order(orders_by_id)
        |> then(&HiEvents.ingest_api_snapshot(integration, "attendee.updated", &1))
      end)

    results = order_results ++ attendee_results

    case Enum.find(results, &match?({:error, _reason}, &1)) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        {:ok,
         %{
           orders: length(orders),
           attendees: length(attendees),
           processed: Enum.count(results, &match?({:ok, :processed, _event}, &1)),
           duplicates: Enum.count(results, &match?({:ok, :duplicate, _event}, &1))
         }}
    end
  end

  defp product_names(orders) do
    Enum.reduce(orders, %{}, &merge_product_names/2)
  end

  defp merge_product_names(order, names) do
    Enum.reduce(order["order_items"] || [], names, &put_product_name/2)
  end

  defp put_product_name(%{"product_id" => product_id, "item_name" => name}, names)
       when not is_nil(product_id) and not is_nil(name),
       do: Map.put(names, to_string(product_id), name)

  defp put_product_name(_item, names), do: names

  defp enrich_order(order, product_names) do
    attendees =
      Enum.map(order["attendees"] || [], &enrich_attendee(&1, product_names))

    Map.put(order, "attendees", attendees)
  end

  defp enrich_attendee(attendee, product_names) do
    product_name = Map.get(product_names, to_string(attendee["product_id"]))

    attendee
    |> maybe_put("product_name", product_name)
    |> maybe_put("ticket_id", attendee["public_id"] || attendee["short_id"])
  end

  defp attach_order(attendee, orders_by_id) do
    order =
      orders_by_id
      |> Map.get(to_string(attendee["order_id"]))
      |> case do
        nil -> attendee["order"]
        order -> Map.drop(order, ["attendees"])
      end

    maybe_put(attendee, "order", order)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp configured_webhook_url do
    :claper
    |> Application.get_env(:hi_events, [])
    |> Keyword.get(:webhook_url)
  end

  defp validate_webhook_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, url}

      _other ->
        {:error, :invalid_webhook_url}
    end
  end

  defp validate_webhook_url(_url), do: {:error, :invalid_webhook_url}
end
