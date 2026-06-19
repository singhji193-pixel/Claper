defmodule Claper.EventApp.Notifications do
  @moduledoc """
  Outbound notification boundary for the attendee PWA.

  Claper owns OTP generation and verification. n8n receives a signed delivery
  instruction when configured, so email design and provider routing can stay
  customizable outside the app.
  """

  alias Claper.EventApp.OtpChallenge
  alias Claper.Events.Event
  alias Claper.HiEvents.EventTicket

  def deliver_attendee_otp(%{
        event: %Event{} = event,
        ticket: %EventTicket{} = ticket,
        challenge: %OtpChallenge{} = challenge,
        code: code
      }) do
    case n8n_webhook_url() do
      nil ->
        {:ok, :disabled}

      "" ->
        {:ok, :disabled}

      url ->
        payload = attendee_otp_payload(event, ticket, challenge, code)
        body = Jason.encode!(payload)

        case Req.post(url,
               body: body,
               headers: [
                 {"content-type", "application/json"},
                 {"x-claper-event", "attendee_otp"},
                 {"x-claper-signature", "sha256=#{signature(n8n_webhook_secret(), body)}"}
               ],
               receive_timeout: 5_000,
               retry: false
             ) do
          {:ok, %{status: status}} when status in 200..299 ->
            {:ok, :sent}

          {:ok, %{status: status, body: response_body}} ->
            {:error, "n8n returned HTTP #{status}: #{truncate_response(response_body)}"}

          {:error, reason} ->
            {:error, Exception.message(reason)}
        end
    end
  end

  def attendee_otp_payload(
        %Event{} = event,
        %EventTicket{} = ticket,
        %OtpChallenge{} = challenge,
        code
      ) do
    %{
      type: "attendee_otp",
      event_id: event.id,
      event_code: event.code,
      event_name: event.name,
      app_url: event_app_url(event),
      verify_url: event_verify_url(event, challenge.email),
      email: challenge.email,
      attendee_name: ticket.attendee_name,
      ticket_name: ticket.ticket_name,
      otp_code: code,
      expires_at: DateTime.to_iso8601(challenge.expires_at),
      expires_in_minutes: expires_in_minutes(challenge.expires_at)
    }
  end

  def signature(secret, body) when is_binary(secret) and is_binary(body) do
    :crypto.mac(:hmac, :sha256, secret, body)
    |> Base.encode16(case: :lower)
  end

  defp expires_in_minutes(%DateTime{} = expires_at) do
    expires_at
    |> DateTime.diff(DateTime.utc_now(), :second)
    |> max(0)
    |> div(60)
  end

  defp event_app_url(%Event{} = event) do
    case public_base_url(event) do
      nil -> "#{base_url()}/app/#{event.code}"
      url -> url
    end
  end

  defp event_verify_url(%Event{} = event, email) do
    "#{event_app_url(event)}/verify?email=#{URI.encode_www_form(email)}"
  end

  defp base_url do
    :claper
    |> Application.get_env(ClaperWeb.Endpoint, [])
    |> Keyword.get(:base_url)
    |> case do
      %URI{} = uri -> URI.to_string(uri)
      url when is_binary(url) -> url
      _ -> "http://localhost:4000"
    end
    |> String.trim_trailing("/")
  end

  defp public_base_url(%Event{} = event) do
    config = Application.get_env(:claper, :event_app, [])
    public_event_code = Keyword.get(config, :public_event_code)
    public_base_url = Keyword.get(config, :public_base_url)

    cond do
      !is_binary(public_base_url) or String.trim(public_base_url) == "" ->
        nil

      is_binary(public_event_code) and String.trim(public_event_code) not in ["", event.code] ->
        nil

      true ->
        public_base_url |> String.trim() |> String.trim_trailing("/")
    end
  end

  defp n8n_webhook_url do
    :claper
    |> Application.get_env(:event_app, [])
    |> Keyword.get(:n8n_webhook_url)
  end

  defp n8n_webhook_secret do
    config = Application.get_env(:claper, :event_app, [])

    Keyword.get(config, :n8n_webhook_secret) ||
      Keyword.get(config, :otp_secret) ||
      endpoint_secret() ||
      "event-app-local-secret"
  end

  defp endpoint_secret do
    :claper
    |> Application.get_env(ClaperWeb.Endpoint, [])
    |> Keyword.get(:secret_key_base)
  end

  defp truncate_response(response_body) do
    response_body
    |> inspect()
    |> String.slice(0, 240)
  end
end
