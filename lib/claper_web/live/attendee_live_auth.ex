defmodule ClaperWeb.AttendeeLiveAuth do
  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign(:attendee_identifier, session["attendee_identifier"])
      |> assign(:event_app_session_token, session["event_app_session_token"])
      |> assign(:current_user, session["current_user"])

    {:cont, socket}
  end
end
