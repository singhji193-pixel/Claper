defmodule Claper.HiEvents.ClientTest do
  use ExUnit.Case, async: true

  alias Claper.HiEvents.Client

  test "logs in without persisting credentials and paginates attendees" do
    request = fn options ->
      case {options[:method], options[:url], options[:params]} do
        {:post, "https://events.example/api/auth/login", nil} ->
          assert options[:json] == %{"email" => "sync@example.com", "password" => "secret"}
          {:ok, %Req.Response{status: 200, body: %{"token" => "short-lived-token"}}}

        {:get, "https://events.example/api/events/3/attendees", [page: 1, per_page: 2]} ->
          assert bearer_header(options) == "Bearer short-lived-token"

          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "data" => [%{"id" => 1}, %{"id" => 2}],
               "meta" => %{"current_page" => 1, "last_page" => 2}
             }
           }}

        {:get, "https://events.example/api/events/3/attendees", [page: 2, per_page: 2]} ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{
               "data" => [%{"id" => 3}],
               "meta" => %{"current_page" => 2, "last_page" => 2}
             }
           }}
      end
    end

    options = client_options(request, per_page: 2)

    assert {:ok, "short-lived-token"} = Client.login(options)

    assert {:ok, [%{"id" => 1}, %{"id" => 2}, %{"id" => 3}]} =
             Client.list_attendees("3", "short-lived-token", options)
  end

  test "returns safe errors for rejected credentials and malformed pagination" do
    unauthorized = fn _options ->
      {:ok, %Req.Response{status: 401, body: %{"message" => "contains sensitive details"}}}
    end

    assert {:error, {:http_error, 401}} = Client.login(client_options(unauthorized))

    malformed = fn _options ->
      {:ok, %Req.Response{status: 200, body: %{"data" => "not-a-list"}}}
    end

    assert {:error, :invalid_response} =
             Client.list_orders("3", "token", client_options(malformed))
  end

  test "rejects missing credentials before making a request" do
    request = fn _options -> flunk("request must not run") end

    assert {:error, :not_configured} =
             Client.login(
               base_url: "https://events.example/api",
               email: nil,
               password: nil,
               request: request
             )
  end

  defp client_options(request, extra \\ []) do
    Keyword.merge(
      [
        base_url: "https://events.example/api",
        email: "sync@example.com",
        password: "secret",
        request: request
      ],
      extra
    )
  end

  defp bearer_header(options) do
    options
    |> Keyword.fetch!(:headers)
    |> Enum.into(%{})
    |> Map.fetch!("authorization")
  end
end
