defmodule ClaperWeb.PwaController do
  use ClaperWeb, :controller

  alias Claper.EventApp

  def bootstrap(conn, %{"code" => code}) do
    attendee_session_token =
      get_session(conn, :event_app_session_token) || get_session(conn, :attendee_identifier)

    case EventApp.bootstrap_event(code, attendee_session_token) do
      {:ok, bootstrap} ->
        json(conn, bootstrap)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "event_not_found"})
    end
  end
end
