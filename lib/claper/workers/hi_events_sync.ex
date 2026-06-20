defmodule Claper.Workers.HiEventsSync do
  @moduledoc false

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 600, states: [:available, :scheduled, :executing, :retryable]]

  alias Claper.HiEvents
  alias Claper.HiEvents.{Client, Integration, Sync}
  alias Claper.Repo

  def enqueue(%Integration{id: id}) do
    %{"integration_id" => id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"integration_id" => integration_id}}) do
    case Repo.get(Integration, integration_id) do
      %Integration{enabled: true} = integration ->
        case Sync.run(integration) do
          {:ok, _details} -> :ok
          {:error, reason} -> {:error, Sync.error_message(reason)}
        end

      _integration ->
        :ok
    end
  end

  def perform(%Oban.Job{}) do
    if Client.configured?(), do: enqueue_enabled_integrations(), else: :ok
  end

  defp enqueue_enabled_integrations do
    HiEvents.list_enabled_integrations()
    |> Enum.reduce_while(:ok, &enqueue_integration/2)
  end

  defp enqueue_integration(integration, :ok) do
    case enqueue(integration) do
      {:ok, _job} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end
end
