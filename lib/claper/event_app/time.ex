defmodule Claper.EventApp.Time do
  @moduledoc """
  Timezone conversion between stored naive-UTC timestamps and event-local
  wall times.

  Agenda `starts_at` values are stored as naive UTC. Organizers enter and
  attendees see wall times in the event timezone configured on
  `Claper.EventApp.Setting`. Invalid timezones fall back to treating the
  value as UTC so display never crashes.
  """

  @utc "Etc/UTC"

  def valid_timezone?(timezone) when is_binary(timezone) and timezone != "" do
    case DateTime.from_naive(~N[2026-01-01 00:00:00], timezone) do
      {:ok, _datetime} -> true
      {:ambiguous, _first, _second} -> true
      {:gap, _just_before, _just_after} -> true
      _error -> false
    end
  end

  def valid_timezone?(_timezone), do: false

  @doc """
  Converts an event-local wall time to naive UTC.

  Ambiguous fall-back times resolve to the earlier instant; nonexistent
  spring-forward times resolve to just after the gap.
  """
  def to_utc(nil, _timezone), do: nil

  def to_utc(%NaiveDateTime{} = local, timezone) do
    case DateTime.from_naive(local, timezone) do
      {:ok, datetime} -> shift_to_utc(datetime)
      {:ambiguous, first, _second} -> shift_to_utc(first)
      {:gap, _just_before, just_after} -> shift_to_utc(just_after)
      {:error, _reason} -> local
    end
  end

  @doc """
  Converts a stored naive-UTC timestamp to the event-local wall time.
  """
  def to_local(nil, _timezone), do: nil

  def to_local(%NaiveDateTime{} = utc, timezone) do
    with {:ok, datetime} <- DateTime.from_naive(utc, @utc),
         {:ok, shifted} <- DateTime.shift_zone(datetime, timezone) do
      DateTime.to_naive(shifted)
    else
      _error -> utc
    end
  end

  @doc """
  Returns the event-local calendar date for a stored naive-UTC timestamp.
  """
  def local_date(nil, _timezone), do: nil

  def local_date(%NaiveDateTime{} = utc, timezone) do
    utc |> to_local(timezone) |> NaiveDateTime.to_date()
  end

  @doc """
  Converts a form `"starts_at"` param entered as event-local wall time into
  naive UTC before it reaches an agenda changeset. Unparseable values pass
  through so changeset validation reports them.
  """
  def convert_starts_at_param(params, timezone) when is_map(params) do
    case Map.fetch(params, "starts_at") do
      {:ok, value} when is_binary(value) and value != "" ->
        case parse_wall_time(value) do
          {:ok, local} -> Map.put(params, "starts_at", to_utc(local, timezone))
          :error -> params
        end

      _missing ->
        params
    end
  end

  defp parse_wall_time(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, local} ->
        {:ok, local}

      {:error, _reason} ->
        # datetime-local inputs omit seconds ("2026-07-25T08:30").
        case NaiveDateTime.from_iso8601(value <> ":00") do
          {:ok, local} -> {:ok, local}
          {:error, _reason} -> :error
        end
    end
  end

  defp shift_to_utc(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!(@utc)
    |> DateTime.to_naive()
  end
end
