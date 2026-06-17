defmodule ClaperWeb.PwaController do
  use ClaperWeb, :controller

  alias Claper.EventApp

  def bootstrap(conn, %{"code" => code}) do
    attendee_identifier = get_session(conn, :attendee_identifier)

    case EventApp.bootstrap_event(code, attendee_identifier) do
      {:ok, bootstrap} ->
        json(conn, bootstrap)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "event_not_found"})
    end
  end
end
