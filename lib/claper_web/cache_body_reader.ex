defmodule ClaperWeb.CacheBodyReader do
  @moduledoc """
  Caches parsed request bodies so webhook controllers can verify signatures.
  """

  import Plug.Conn

  def read_body(conn, opts) do
    if json_request?(conn) do
      read_json_body(conn, opts, "")
    else
      Plug.Conn.read_body(conn, opts)
    end
  end

  defp read_json_body(conn, opts, acc) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        body = acc <> body
        {:ok, body, assign(conn, :raw_body, body)}

      {:more, body, conn} ->
        read_json_body(conn, opts, acc <> body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp json_request?(conn) do
    conn
    |> get_req_header("content-type")
    |> Enum.any?(&String.contains?(&1, "json"))
  end
end
