defmodule Claper.HiEvents.Client do
  @moduledoc """
  Minimal authenticated client for the self-hosted Hi.Events organizer API.

  Credentials are read at runtime and exchanged for a short-lived bearer token
  for each sync run. Neither credentials nor response bodies are logged.
  """

  @default_per_page 100
  @max_pages 100

  def configured?(options \\ []) do
    case resolved_config(options) do
      {:ok, _config} -> true
      {:error, _reason} -> false
    end
  end

  def login(options \\ []) do
    with {:ok, config} <- resolved_config(options),
         {:ok, response} <-
           request(config,
             method: :post,
             url: api_url(config.base_url, "/auth/login"),
             json: login_payload(config)
           ),
         {:ok, body} <- successful_body(response),
         token when is_binary(token) and token != "" <- body["token"] do
      {:ok, token}
    else
      nil -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_response}
    end
  end

  def list_orders(event_id, token, options \\ []) do
    list_paginated(event_id, "orders", token, options)
  end

  def list_attendees(event_id, token, options \\ []) do
    list_paginated(event_id, "attendees", token, options)
  end

  def list_webhooks(event_id, token, options \\ []) do
    list_paginated(event_id, "webhooks", token, options)
  end

  def create_webhook(event_id, token, attrs, options \\ []) do
    with {:ok, config} <- resolved_config(options),
         {:ok, response} <-
           request(config,
             method: :post,
             url: event_url(config.base_url, event_id, "webhooks"),
             headers: authorization_headers(token),
             json: attrs
           ),
         {:ok, body} <- successful_body(response),
         webhook when is_map(webhook) <- resource(body),
         id when not is_nil(id) <- webhook["id"],
         secret when is_binary(secret) and secret != "" <- webhook["secret"] do
      {:ok, webhook |> Map.put("id", to_string(id)) |> Map.put("secret", secret)}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_response}
    end
  end

  def update_webhook(event_id, webhook_id, token, attrs, options \\ []) do
    with {:ok, config} <- resolved_config(options),
         {:ok, response} <-
           request(config,
             method: :put,
             url: event_url(config.base_url, event_id, "webhooks/#{path_segment(webhook_id)}"),
             headers: authorization_headers(token),
             json: attrs
           ),
         {:ok, body} <- successful_body(response),
         webhook when is_map(webhook) <- resource(body) do
      {:ok, webhook}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_response}
    end
  end

  defp list_paginated(event_id, resource_name, token, options) do
    with {:ok, config} <- resolved_config(options) do
      per_page = normalize_per_page(config.per_page)

      fetch_pages(
        config,
        event_url(config.base_url, event_id, resource_name),
        token,
        1,
        per_page,
        []
      )
    end
  end

  defp fetch_pages(_config, _url, _token, page, _per_page, _items) when page > @max_pages,
    do: {:error, :page_limit_exceeded}

  defp fetch_pages(config, url, token, page, per_page, items) do
    with {:ok, response} <-
           request(config,
             method: :get,
             url: url,
             headers: authorization_headers(token),
             params: [page: page, per_page: per_page]
           ),
         {:ok, body} <- successful_body(response),
         data when is_list(data) <- body["data"],
         {:ok, last_page} <- last_page(body, page, data, per_page) do
      accumulated = items ++ data

      if page < last_page do
        fetch_pages(config, url, token, page + 1, per_page, accumulated)
      else
        {:ok, accumulated}
      end
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_response}
    end
  end

  defp last_page(%{"meta" => %{"last_page" => last_page}}, _page, _data, _per_page)
       when is_integer(last_page) and last_page > @max_pages,
       do: {:error, :page_limit_exceeded}

  defp last_page(%{"meta" => %{"last_page" => last_page}}, _page, _data, _per_page)
       when is_integer(last_page) and last_page > 0,
       do: {:ok, last_page}

  defp last_page(_body, page, data, per_page) when length(data) < per_page, do: {:ok, page}
  defp last_page(_body, page, _data, _per_page), do: {:ok, page + 1}

  defp successful_body(%Req.Response{status: status, body: body})
       when status >= 200 and status < 300 and is_map(body),
       do: {:ok, body}

  defp successful_body(%Req.Response{status: status}), do: {:error, {:http_error, status}}

  defp request(config, request_options) do
    options =
      Keyword.merge(
        [
          receive_timeout: config.receive_timeout,
          connect_options: [timeout: config.connect_timeout],
          retry: false
        ],
        request_options
      )

    case config.request.(options) do
      {:ok, %Req.Response{} = response} -> {:ok, response}
      {:error, _reason} -> {:error, :transport_error}
      _other -> {:error, :transport_error}
    end
  rescue
    _error -> {:error, :transport_error}
  end

  defp resolved_config(options) do
    config =
      :claper
      |> Application.get_env(:hi_events, [])
      |> Keyword.merge(options)

    base_url = config[:base_url]
    email = config[:email]
    password = config[:password]

    if valid_base_url?(base_url) and present?(email) and present?(password) do
      {:ok,
       %{
         base_url: String.trim_trailing(base_url, "/"),
         email: String.trim(email),
         password: password,
         account_id: config[:account_id],
         per_page: config[:per_page] || @default_per_page,
         connect_timeout: config[:connect_timeout] || 5_000,
         receive_timeout: config[:receive_timeout] || 10_000,
         request: config[:request] || (&Req.request/1)
       }}
    else
      {:error, :not_configured}
    end
  end

  defp login_payload(config) do
    %{"email" => config.email, "password" => config.password}
    |> maybe_put("account_id", config.account_id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp event_url(base_url, event_id, resource) do
    api_url(base_url, "/events/#{path_segment(event_id)}/#{resource}")
  end

  defp api_url(base_url, path), do: base_url <> path

  defp path_segment(value) do
    value
    |> to_string()
    |> URI.encode(&URI.char_unreserved?/1)
  end

  defp authorization_headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
  end

  defp resource(%{"data" => data}) when is_map(data), do: data
  defp resource(data) when is_map(data), do: data
  defp resource(_data), do: nil

  defp normalize_per_page(value) when is_integer(value), do: value |> max(1) |> min(100)
  defp normalize_per_page(_value), do: @default_per_page

  defp valid_base_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        String.trim(host) != ""

      _other ->
        false
    end
  end

  defp valid_base_url?(_url), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
