defmodule ClaperWeb.EventLive.BingoManage do
  use ClaperWeb, :live_view

  alias Claper.Bingos
  alias Claper.Bingos.BingoPrompt

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    {:ok,
     socket
     |> assign(:event, nil)
     |> assign(:prompts, [])
     |> assign(:prompt, nil)
     |> assign(:form, nil)
     |> assign(:settings, nil)
     |> assign(:settings_form, nil)
     |> assign(:stats, Bingos.dashboard_stats(nil))
     |> assign(:leaderboard, [])
     |> assign(:join_url, nil)
     |> assign(:page_title, gettext("Bingo"))}
  end

  @impl true
  def handle_params(%{"code" => code} = params, _url, socket) do
    with {:ok, event} <- load_event(socket, code) do
      {:noreply,
       socket
       |> assign(:event, event)
       |> reload_bingo()
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
  def handle_event("validate", %{"bingo_prompt" => prompt_params}, socket) do
    changeset =
      socket.assigns.prompt
      |> Bingos.change_prompt(force_event(prompt_params, socket.assigns.event))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"bingo_prompt" => prompt_params}, socket) do
    save_prompt(socket, socket.assigns.live_action, prompt_params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    prompt = Bingos.get_prompt_for_event!(socket.assigns.event.id, id)
    {:ok, _prompt} = Bingos.delete_prompt(prompt)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Bingo prompt deleted successfully"))
     |> reload_bingo()}
  end

  def handle_event("move", %{"id" => id, "direction" => direction}, socket) do
    direction =
      case direction do
        "up" -> :up
        "down" -> :down
        _ -> nil
      end

    case Bingos.move_prompt(socket.assigns.event.id, id, direction) do
      {:ok, _prompts} -> :ok
      {:error, _reason} -> :ok
    end

    {:noreply, reload_bingo(socket)}
  end

  def handle_event("save-settings", %{"bingo_setting" => settings_params}, socket) do
    case Bingos.update_settings(socket.assigns.settings, settings_params) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Settings saved"))
         |> reload_bingo()}

      {:error, changeset} ->
        {:noreply, assign(socket, :settings_form, to_form(changeset))}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, push_patch(socket, to: bingo_path(socket.assigns.event))}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Bingo"))
    |> assign(:prompt, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    prompt = %BingoPrompt{
      event_id: socket.assigns.event.id,
      position: Bingos.next_position(socket.assigns.event.id)
    }

    socket
    |> assign(:page_title, gettext("New Bingo prompt"))
    |> assign(:prompt, prompt)
    |> assign_form(Bingos.change_prompt(prompt))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    prompt = Bingos.get_prompt_for_event!(socket.assigns.event.id, id)

    socket
    |> assign(:page_title, gettext("Edit Bingo prompt"))
    |> assign(:prompt, prompt)
    |> assign_form(Bingos.change_prompt(prompt))
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
    Claper.Events.led_by?(current_user.email, event) ||
      (event.user && event.user.id == current_user.id)
  end

  defp reload_bingo(%{assigns: %{event: nil}} = socket), do: socket

  defp reload_bingo(socket) do
    event = socket.assigns.event
    settings = Bingos.get_or_create_settings(event.id)

    socket
    |> assign(:prompts, Bingos.list_prompts(event.id))
    |> assign(:settings, settings)
    |> assign(:settings_form, to_form(Bingos.change_settings(settings)))
    |> assign(:stats, Bingos.dashboard_stats(event.id))
    |> assign(:leaderboard, Bingos.leaderboard(event.id))
    |> assign(:join_url, url(~p"/e/#{event.code}/bingo"))
  end

  defp save_prompt(socket, :new, prompt_params) do
    case Bingos.create_prompt(force_event(prompt_params, socket.assigns.event)) do
      {:ok, _prompt} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Bingo prompt saved successfully"))
         |> push_navigate(to: bingo_path(socket.assigns.event))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_prompt(socket, :edit, prompt_params) do
    case Bingos.update_prompt(
           socket.assigns.prompt,
           force_event(prompt_params, socket.assigns.event)
         ) do
      {:ok, _prompt} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Bingo prompt saved successfully"))
         |> push_navigate(to: bingo_path(socket.assigns.event))}

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
    |> Map.put_new("position", Bingos.next_position(event.id))
  end

  defp bingo_path(event), do: ~p"/e/#{event.code}/manage/bingo"
end
