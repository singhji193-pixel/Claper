defmodule ClaperWeb.AdminLive.AgendaLive do
  use ClaperWeb, :live_view

  alias Claper.Admin
  alias Claper.Agendas
  alias Claper.Agendas.AgendaItem

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    events = Admin.list_all_events()

    {:ok,
     socket
     |> assign(:page_title, gettext("Agenda"))
     |> assign(:events, events)
     |> assign(:event_options, event_options(events))
     |> assign(:selected_event_id, nil)
     |> assign(:selected_event, nil)
     |> assign(:agenda_items, [])
     |> assign(:agenda_item, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(:page_title, gettext("Agenda"))
    |> assign(:agenda_item, nil)
    |> assign_selected_event(params["event_id"])
  end

  defp apply_action(socket, :new, params) do
    socket = assign_selected_event(socket, params["event_id"])
    event_id = socket.assigns.selected_event_id

    socket
    |> assign(:page_title, gettext("New agenda item"))
    |> assign(:agenda_item, %AgendaItem{
      event_id: event_id,
      position: Agendas.next_position(event_id),
      starts_at: default_starts_at(socket.assigns.selected_event)
    })
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    agenda_item = Agendas.get_agenda_item!(id, [:event])

    socket
    |> assign(:page_title, gettext("Edit agenda item"))
    |> assign(:agenda_item, agenda_item)
    |> assign_selected_event("#{agenda_item.event_id}")
  end

  @impl true
  def handle_event("select-event", %{"event_id" => event_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/agenda?event_id=#{event_id}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    agenda_item = Agendas.get_agenda_item_for_event!(socket.assigns.selected_event_id, id)
    {:ok, _agenda_item} = Agendas.delete_agenda_item(agenda_item)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Agenda item deleted successfully"))
     |> reload_agenda_items()}
  end

  def handle_event("move", %{"id" => id, "direction" => direction}, socket) do
    direction =
      case direction do
        "up" -> :up
        "down" -> :down
        _ -> nil
      end

    case Agendas.move_agenda_item(socket.assigns.selected_event_id, id, direction) do
      {:ok, _items} -> :ok
      {:error, _reason} -> :ok
    end

    {:noreply, reload_agenda_items(socket)}
  end

  @impl true
  def handle_info({ClaperWeb.AdminLive.AgendaLive.FormComponent, {:saved, agenda_item}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Agenda item saved successfully"))
     |> push_navigate(to: ~p"/admin/agenda?event_id=#{agenda_item.event_id}")}
  end

  defp assign_selected_event(socket, event_id_param) do
    event_id = selected_event_id(event_id_param, socket.assigns.events)
    selected_event = Enum.find(socket.assigns.events, &(&1.id == event_id))

    socket
    |> assign(:selected_event_id, event_id)
    |> assign(:selected_event, selected_event)
    |> reload_agenda_items()
  end

  defp reload_agenda_items(%{assigns: %{selected_event_id: nil}} = socket) do
    assign(socket, :agenda_items, [])
  end

  defp reload_agenda_items(socket) do
    assign(socket, :agenda_items, Agendas.list_agenda_items(socket.assigns.selected_event_id))
  end

  defp selected_event_id(nil, events), do: events |> List.first() |> event_id()
  defp selected_event_id("", events), do: events |> List.first() |> event_id()

  defp selected_event_id(event_id, events) do
    parsed_id = parse_id(event_id)

    if Enum.any?(events, &(&1.id == parsed_id)) do
      parsed_id
    else
      events |> List.first() |> event_id()
    end
  end

  defp event_id(nil), do: nil
  defp event_id(event), do: event.id

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp event_options(events) do
    Enum.map(events, fn event ->
      {"#{event.name} (#{String.upcase(event.code)})", event.id}
    end)
  end

  defp default_starts_at(nil) do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end

  defp default_starts_at(event), do: event.started_at

  def format_agenda_time(%NaiveDateTime{} = starts_at) do
    Calendar.strftime(starts_at, "%Y-%m-%d %H:%M")
  end

  def format_duration(nil), do: gettext("No duration")
  def format_duration(minutes), do: gettext("%{count} min", count: minutes)
end
