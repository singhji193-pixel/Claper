defmodule ClaperWeb.EventController do
  use ClaperWeb, :controller

  alias Claper.EventApp

  def attendee_identifier(conn, _opts) do
    conn |> set_token()
  end

  defp set_token(conn) do
    case authenticated_interaction_key(conn) do
      interaction_key when is_binary(interaction_key) ->
        put_session(conn, :attendee_identifier, interaction_key)

      nil ->
        if is_nil(get_session(conn, :attendee_identifier)) do
          put_session(conn, :attendee_identifier, Base.url_encode64(:crypto.strong_rand_bytes(8)))
        else
          conn
        end
    end
  end

  defp authenticated_interaction_key(conn) do
    with event_id when not is_nil(event_id) <- event_id(conn.params),
         token when is_binary(token) <- get_session(conn, :event_app_session_token),
         {:ok, identity} <- EventApp.interaction_identity(event_id, token) do
      identity.interaction_key
    else
      _ -> nil
    end
  end

  defp event_id(%{"code" => code}) do
    case Claper.Events.get_event_with_code(code) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp event_id(_params), do: nil

  def slide_generate(conn, %{"uuid" => uuid, "qr" => qr} = _opts) do
    with event <- Claper.Events.get_event!(uuid) do
      "data:image/png;base64," <> raw = qr
      {:ok, data} = Base.decode64(raw)
      dir = System.tmp_dir!()
      tmp_file = Path.join(dir, "qr-#{uuid}.png")
      File.write!(tmp_file, data, [:binary])

      code = String.upcase(event.code)

      {output, 0} =
        System.cmd("convert", [
          "-size",
          "1920x1080",
          "xc:black",
          "-fill",
          "white",
          "-font",
          "Roboto",
          "-pointsize",
          "45",
          "-gravity",
          "north",
          "-annotate",
          "+0+100",
          "Scannez pour interagir en temps-réel",
          "-gravity",
          "center",
          "-annotate",
          "+0+200",
          "Ou utilisez le code:",
          "-pointsize",
          "65",
          "-gravity",
          "center",
          "-annotate",
          "+0+350",
          "##{code}",
          tmp_file,
          "-gravity",
          "north",
          "-geometry",
          "+0+230",
          "-composite",
          "jpg:-"
        ])

      conn
      |> put_resp_content_type("image/png")
      |> send_resp(200, output)
    end
  end
end
