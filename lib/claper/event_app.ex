defmodule Claper.EventApp do
  @moduledoc """
  Event companion app settings and bootstrap helpers.
  """

  alias Claper.{Agendas, Bingos, Events, Repo}
  alias Claper.EventApp.Setting
  alias Claper.Events.Event

  def get_settings(event_id), do: Repo.get_by(Setting, event_id: event_id)

  def settings_for_event(event_id) do
    get_settings(event_id) || %Setting{event_id: event_id}
  end

  def get_or_create_settings(event_id) do
    case get_settings(event_id) do
      %Setting{} = setting ->
        setting

      nil ->
        %Setting{}
        |> Setting.changeset(%{event_id: event_id})
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target: :event_id
        )

        get_settings(event_id)
    end
  end

  def change_settings(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  def bootstrap_event(code, attendee_identifier \\ nil) do
    case Events.get_event_with_code(code) do
      %Event{} = event -> {:ok, bootstrap_for_event(event, attendee_identifier)}
      nil -> {:error, :not_found}
    end
  end

  def bootstrap_for_event(%Event{} = event, attendee_identifier \\ nil) do
    agenda_items = Agendas.list_agenda_items(event.id)
    bingo_prompts = Bingos.list_prompts(event.id)
    settings = settings_for_event(event.id)

    %{
      event: public_event(event),
      settings: Setting.public(settings),
      features: %{
        agenda: feature("Agenda", true, length(agenda_items), "/app/#{event.code}/agenda"),
        bingo: feature("Bingo", true, length(bingo_prompts), "/app/#{event.code}/bingo"),
        people: feature("People", settings.people_enabled, 0, "/app/#{event.code}/people"),
        ticket: feature("Ticket", settings.ticket_enabled, 0, "/app/#{event.code}/ticket"),
        chat: feature("Chat", settings.chat_enabled, 0, "/app/#{event.code}/chat"),
        sponsors: feature("Sponsors", settings.sponsors_enabled, 0, "/app/#{event.code}/sponsors")
      },
      attendee: %{
        authenticated: false,
        identifier_present: is_binary(attendee_identifier) and byte_size(attendee_identifier) > 0
      }
    }
  end

  defp feature(label, enabled, count, href) do
    %{
      label: label,
      enabled: enabled,
      available: enabled and count > 0,
      count: count,
      href: href
    }
  end

  defp public_event(%Event{} = event) do
    %{
      id: event.id,
      uuid: event.uuid,
      code: event.code,
      name: event.name,
      started_at: format_time(event.started_at),
      expired_at: format_time(event.expired_at)
    }
  end

  defp format_time(nil), do: nil
  defp format_time(%NaiveDateTime{} = time), do: NaiveDateTime.to_iso8601(time)
end
