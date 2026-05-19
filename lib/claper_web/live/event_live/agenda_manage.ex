defmodule ClaperWeb.EventLive.AgendaManage do
  use ClaperWeb, :live_view

  alias Claper.Agendas
  alias Claper.Agendas.AgendaItem

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    {:ok,
     socket
     |> assign(:event, nil)
     |> assign(:agenda_items, [])
     |> assign(:agenda_item, nil)
     |> assign(:form, nil)
     |> assign(:page_title, gettext("Agenda"))}
  end

  @impl true
  def handle_params(%{"code" => code} = params, _url, socket) do
    with {:ok, event} <- load_event(socket, code) do
      {:noreply,
       socket
       |> assign(:event, event)
       |> reload_agenda_items()
       |> apply_action(socket.assigns.live_action, params)}
    else
      :error ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Event doesn't exist"))
         |> redirect(to: ~p"/events")}
    end
  end

  @impl true
  def handle_event("validate", %{"agenda_item" => agenda_item_params}, socket) do
    changeset =
      socket.assigns.agenda_item
      |> Agendas.change_agenda_item(force_event(agenda_item_params, socket.assigns.event))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"agenda_item" => agenda_item_params}, socket) do
    save_agenda_item(socket, socket.assigns.live_action, agenda_item_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    agenda_item = Agendas.get_agenda_item_for_event!(socket.assigns.event.id, id)
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

    case Agendas.move_agenda_item(socket.assigns.event.id, id, direction) do
      {:ok, _items} -> :ok
      {:error, _reason} -> :ok
    end

    {:noreply, reload_agenda_items(socket)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, push_patch(socket, to: agenda_path(socket.assigns.event))}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Agenda"))
    |> assign(:agenda_item, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    agenda_item = %AgendaItem{
      event_id: socket.assigns.event.id,
      position: Agendas.next_position(socket.assigns.event.id),
      starts_at: default_starts_at(socket.assigns.event)
    }

    socket
    |> assign(:page_title, gettext("New agenda item"))
    |> assign(:agenda_item, agenda_item)
    |> assign_form(Agendas.change_agenda_item(agenda_item))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    agenda_item = Agendas.get_agenda_item_for_event!(socket.assigns.event.id, id)

    socket
    |> assign(:page_title, gettext("Edit agenda item"))
    |> assign(:agenda_item, agenda_item)
    |> assign_form(Agendas.change_agenda_item(agenda_item))
  end

  defp load_event(%{assigns: %{current_user: current_user}}, code) do
    event = Claper.Events.get_event_with_code(code, [:user])

    if event && leader?(current_user, event) do
      {:ok, event}
    else
      :error
    end
  end

  defp leader?(current_user, event) do
    Claper.Events.led_by?(current_user.email, event) || event.user.id == current_user.id
  end

  defp reload_agenda_items(%{assigns: %{event: nil}} = socket), do: socket

  defp reload_agenda_items(socket) do
    assign(socket, :agenda_items, Agendas.list_agenda_items(socket.assigns.event.id))
  end

  defp save_agenda_item(socket, :new, agenda_item_params) do
    case Agendas.create_agenda_item(force_event(agenda_item_params, socket.assigns.event)) do
      {:ok, _agenda_item} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Agenda item saved successfully"))
         |> push_navigate(to: agenda_path(socket.assigns.event))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_agenda_item(socket, :edit, agenda_item_params) do
    case Agendas.update_agenda_item(
           socket.assigns.agenda_item,
           force_event(agenda_item_params, socket.assigns.event)
         ) do
      {:ok, _agenda_item} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Agenda item saved successfully"))
         |> push_navigate(to: agenda_path(socket.assigns.event))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp force_event(params, event) do
    params
    |> Map.put("event_id", event.id)
    |> Map.put_new("position", Agendas.next_position(event.id))
  end

  defp default_starts_at(event), do: event.started_at || NaiveDateTime.utc_now()

  defp agenda_path(event), do: ~p"/e/#{event.code}/manage/agenda"

  def format_agenda_time(%NaiveDateTime{} = starts_at) do
    Calendar.strftime(starts_at, "%Y-%m-%d %H:%M")
  end

  def format_duration(nil), do: gettext("No duration")
  def format_duration(minutes), do: gettext("%{count} min", count: minutes)
end
