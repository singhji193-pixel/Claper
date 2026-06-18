defmodule ClaperWeb.PwaAuthController do
  use ClaperWeb, :controller

  alias Claper.{EventApp, Events}

  def new(conn, %{"code" => code} = params) do
    render_login(conn, code, params["email"], nil)
  end

  def create(conn, %{"code" => code, "attendee" => %{"email" => email}}) do
    case EventApp.request_login_code(code, email, request_metadata(conn)) do
      {:ok, %{event: event, delivery_status: delivery_status}} ->
        conn
        |> put_flash(:info, delivery_message(delivery_status))
        |> redirect(to: ~p"/app/#{event.code}/verify?email=#{email}")

      {:error, reason} ->
        render_login(conn, code, email, error_message(reason))
    end
  end

  def verify(conn, %{"code" => code} = params) do
    render_verify(conn, code, params["email"], nil)
  end

  def verify_code(conn, %{"code" => code, "attendee" => %{"email" => email, "code" => otp}}) do
    case EventApp.verify_login_code(code, email, otp, request_metadata(conn)) do
      {:ok, %{event: event, token: token}} ->
        conn
        |> put_session(:event_app_session_token, token)
        |> put_session(:attendee_identifier, token)
        |> put_flash(:info, gettext("You are signed in."))
        |> redirect(to: ~p"/app/#{event.code}/profile")

      {:error, reason} ->
        render_verify(conn, code, email, error_message(reason))
    end
  end

  def delete(conn, %{"code" => code}) do
    conn
    |> get_session(:event_app_session_token)
    |> EventApp.sign_out_attendee_session()

    conn
    |> delete_session(:event_app_session_token)
    |> put_flash(:info, gettext("You are signed out."))
    |> redirect(to: ~p"/app/#{code}")
  end

  defp render_login(conn, code, email, error_message) do
    render_auth(conn, "new.html", code, email, error_message)
  end

  defp render_verify(conn, code, email, error_message) do
    render_auth(conn, "verify.html", code, email, error_message)
  end

  defp render_auth(conn, template, code, email, error_message) do
    event = Events.get_event_with_code(code)

    conn
    |> assign(:event, event)
    |> assign(:event_code, code)
    |> assign(:email, email)
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
end
