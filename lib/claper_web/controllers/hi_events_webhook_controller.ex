defmodule ClaperWeb.HiEventsWebhookController do
  use ClaperWeb, :controller

  alias Claper.HiEvents

  def create(conn, params) do
    raw_body = conn.assigns[:raw_body] || ""

    conn
    |> send_ingest_response(HiEvents.ingest_webhook(conn.req_headers, raw_body, params))
  end

  defp send_ingest_response(conn, result) do
    case result do
      {:ok, :processed, sync_event} ->
        conn
        |> put_status(:accepted)
        |> json(%{data: %{status: "processed", id: sync_event.id}})

      {:ok, :duplicate, sync_event} ->
        conn
        |> put_status(:accepted)
        |> json(%{data: %{status: "duplicate", id: sync_event.id}})

      {:error, :unknown_event} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "unknown_hi_events_event"})

      {:error, :disabled} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "integration_disabled"})

      {:error, reason} when reason in [:missing_signature, :invalid_signature] ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: to_string(reason)})

      {:error, reason} when reason in [:invalid_json, :invalid_payload, :missing_event_id] ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: to_string(reason)})

      {:error, {:processing_failed, _reason}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "processing_failed"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "webhook_rejected"})
    end
  end
end
