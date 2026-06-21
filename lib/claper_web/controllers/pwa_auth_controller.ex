defmodule ClaperWeb.PwaAuthController do
  use ClaperWeb, :controller

  alias Claper.{EventApp, Events}
  alias ClaperWeb.PwaLive.App, as: PwaApp

  def new(conn, params) do
    render_login(conn, event_code(params), vanity?(params), params["email"], params["next"], nil)
  end

  def create(conn, %{"attendee" => %{"email" => email}} = params) do
    code = event_code(params)
    vanity = vanity?(params)
    next_path = next_path(params)

    case EventApp.request_login_code(code, email, request_metadata(conn)) do
      {:ok, %{event: event, delivery_status: delivery_status}} ->
        conn
        |> put_flash(:info, delivery_message(delivery_status))
        |> redirect(
          to:
            PwaApp.app_path(
              route_source(event.code, vanity),
              "/verify?#{URI.encode_query(compact_params(email: email, next: next_path))}"
            )
        )

      {:error, reason} ->
        render_login(conn, code, vanity, email, next_path, error_message(reason))
    end
  end

  def verify(conn, params) do
    render_verify(conn, event_code(params), vanity?(params), params["email"], params["next"], nil)
  end

  def verify_code(conn, %{"attendee" => %{"email" => email, "code" => otp}} = params) do
    code = event_code(params)
    vanity = vanity?(params)
    next_path = next_path(params)

    case EventApp.verify_login_code(code, email, otp, request_metadata(conn)) do
      {:ok, %{event: event, attendee: attendee, token: token}} ->
        claim_legacy_identity(conn, event.id, attendee)

        conn
        |> put_session(:event_app_session_token, token)
        |> put_session(:attendee_identifier, attendee.interaction_key)
        |> put_flash(:info, gettext("You are signed in."))
        |> redirect(to: safe_next_path(next_path, route_source(event.code, vanity)))

      {:error, reason} ->
        render_verify(conn, code, vanity, email, next_path, error_message(reason))
    end
  end

  def delete(conn, params) do
    code = event_code(params)

    conn
    |> get_session(:event_app_session_token)
    |> EventApp.sign_out_attendee_session()

    conn
    |> delete_session(:event_app_session_token)
    |> delete_session(:attendee_identifier)
    |> put_flash(:info, gettext("You are signed out."))
    |> redirect(to: PwaApp.app_path(route_source(code, vanity?(params))))
  end

  defp render_login(conn, code, vanity, email, next_path, error_message) do
    render_auth(conn, "new.html", code, vanity, email, next_path, error_message)
  end

  defp render_verify(conn, code, vanity, email, next_path, error_message) do
    render_auth(conn, "verify.html", code, vanity, email, next_path, error_message)
  end

  defp render_auth(conn, template, code, vanity, email, next_path, error_message) do
    event = code && Events.get_event_with_code(code)

    conn
    |> assign(:event, event)
    |> assign(:event_code, code || "")
    |> assign(:vanity, vanity)
    |> assign(:email, email)
    |> assign(:next_path, next_path)
    |> assign(:error_message, error_message)
    |> assign(:page_title, page_title(template))
    |> render(template)
  end

  defp page_title("verify.html"), do: gettext("Enter code")
  defp page_title(_template), do: gettext("Sign in")

  defp request_metadata(conn) do
    [
      request_ip: remote_ip(conn),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    ]
  end

  defp claim_legacy_identity(conn, event_id, attendee) do
    case get_session(conn, :attendee_identifier) do
      identifier when is_binary(identifier) ->
        EventApp.claim_legacy_identity(event_id, attendee, identifier)

      _ ->
        :ok
    end
  end

  defp remote_ip(%{remote_ip: remote_ip}) when is_tuple(remote_ip) do
    remote_ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp remote_ip(_conn), do: nil

  defp delivery_message("disabled") do
    gettext("Code created. Email delivery will start after the n8n webhook is connected.")
  end

  defp delivery_message("failed") do
    gettext("Code created, but delivery failed. Try again shortly or contact the organizer.")
  end

  defp delivery_message(_status), do: gettext("Check your email for the 4-digit code.")

  defp error_message(:event_not_found), do: gettext("This event app is not available.")
  defp error_message(:invalid_email), do: gettext("Enter a valid email address.")

  defp error_message(:ticket_not_found) do
    gettext("No active ticket was found for that email.")
  end

  defp error_message(:too_many_requests) do
    gettext("Too many codes were requested. Try again in a few minutes.")
  end

  defp error_message(:too_soon), do: gettext("Wait a moment before requesting another code.")
  defp error_message(:code_not_requested), do: gettext("Request a new code to continue.")
  defp error_message(:code_expired), do: gettext("That code expired. Request a new one.")
  defp error_message(:invalid_code), do: gettext("That code is not correct.")

  defp error_message(:too_many_attempts) do
    gettext("Too many attempts. Request a new code.")
  end

  defp error_message(_reason), do: gettext("Something went wrong. Try again.")

  defp event_code(params), do: Map.get(params, "code") || public_event_code()

  defp vanity?(params), do: !Map.has_key?(params, "code")

  defp route_source(code, vanity), do: %{event_code: code, vanity: vanity}

  defp next_path(%{"attendee" => %{"next" => next}}), do: next_path(%{"next" => next})

  defp next_path(%{"next" => next}) when is_binary(next), do: String.trim(next)

  defp next_path(_params), do: nil

  defp safe_next_path(next, route_source) do
    default_path = PwaApp.app_path(route_source)

    case sanitize_relative_next(next) do
      nil -> default_path
      path -> if allowed_app_path?(path, route_source), do: path, else: default_path
    end
  end

  defp sanitize_relative_next(nil), do: nil
  defp sanitize_relative_next(""), do: nil

  defp sanitize_relative_next(next) when is_binary(next) do
    case URI.parse(next) do
      %URI{scheme: nil, host: nil, path: path} when is_binary(path) ->
        path = if String.starts_with?(path, "/"), do: path, else: "/#{path}"
        query = URI.parse(next).query

        if query, do: "#{path}?#{query}", else: path

      _ ->
        nil
    end
  end

  defp allowed_app_path?(next, %{vanity: true}) do
    path = next |> URI.parse() |> Map.get(:path)

    path == "/" or
      Enum.any?(
        ["/agenda", "/people", "/scan", "/bingo", "/ticket", "/profile", "/live"],
        fn allowed ->
          path == allowed or String.starts_with?(path, allowed <> "/")
        end
      )
  end

  defp allowed_app_path?(next, %{event_code: code}) when is_binary(code) do
    path = next |> URI.parse() |> Map.get(:path)
    base = "/app/#{code}"

    path == base or
      Enum.any?(
        ["/agenda", "/people", "/scan", "/bingo", "/ticket", "/profile", "/live"],
        fn suffix ->
          path == base <> suffix or String.starts_with?(path, base <> suffix <> "/")
        end
      )
  end

  defp allowed_app_path?(_next, _route_source), do: false

  defp compact_params(params) do
    params
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp public_event_code do
    :claper
    |> Application.get_env(:event_app, [])
    |> Keyword.get(:public_event_code)
    |> case do
      code when is_binary(code) -> String.trim(code)
      _ -> nil
    end
    |> case do
      "" -> nil
      code -> code
    end
  end
end
