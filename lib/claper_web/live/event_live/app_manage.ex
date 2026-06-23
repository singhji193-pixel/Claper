defmodule ClaperWeb.EventLive.AppManage do
  use ClaperWeb, :live_view

  alias Claper.{EventApp, HiEvents}
  alias Claper.HiEvents.{Client, Integration}
  alias Claper.Workers.HiEventsSync

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    {:ok,
     socket
     |> assign(:event, nil)
     |> assign(:integration, nil)
     |> assign(:form, nil)
     |> assign(:app_settings, nil)
     |> assign(:app_settings_form, nil)
     |> assign(:app_settings_status, :idle)
     |> assign(:stats, HiEvents.dashboard_stats(nil))
     |> assign(:webhook_url, nil)
     |> assign(:legacy_webhook_url, nil)
     |> assign(:sync_available, Client.configured?())
     |> assign(:app_url, nil)
     |> assign(:page_title, gettext("Event app"))}
  end

  @impl true
  def handle_params(%{"code" => code}, _url, socket) do
    case load_event(socket, code) do
      {:ok, event} ->
        {:noreply,
         socket
         |> assign(:event, event)
         |> reload_integration()}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Event doesn't exist"))
         |> redirect(to: ~p"/events")}
    end
  end

  @impl true
  def handle_event("validate", %{"integration" => integration_params}, socket) do
    changeset =
      socket.assigns.integration
      |> HiEvents.change_integration(force_event(integration_params, socket.assigns.event))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"integration" => integration_params}, socket) do
    case HiEvents.upsert_integration(socket.assigns.event.id, integration_params) do
      {:ok, _integration} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Hi.Events integration saved"))
         |> reload_integration()}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("save-app-settings", %{"setting" => params}, socket) do
    case EventApp.update_settings(
           socket.assigns.app_settings,
           Map.put(params, "event_id", socket.assigns.event.id)
         ) do
      {:ok, _settings} ->
        broadcast_app_settings(socket.assigns.event)

        {:noreply,
         socket
         |> assign(:app_settings_status, :saved)
         |> reload_integration()}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:app_settings_status, :error)
         |> assign(:app_settings_form, to_form(changeset, as: :setting))}
    end
  end

  def handle_event(
        "rotate-secret",
        _params,
        %{assigns: %{integration: %Integration{id: nil}}} = socket
      ) do
    {:noreply,
     put_flash(socket, :error, gettext("Save the integration before rotating the secret"))}
  end

  def handle_event(
        "rotate-secret",
        _params,
        %{assigns: %{integration: %Integration{remote_webhook_id: id}}} = socket
      )
      when not is_nil(id) do
    {:noreply,
     put_flash(socket, :error, gettext("The native webhook secret is managed automatically"))}
  end

  def handle_event("rotate-secret", _params, socket) do
    case HiEvents.rotate_webhook_secret(socket.assigns.integration) do
      {:ok, _integration} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Webhook secret rotated"))
         |> reload_integration()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not rotate the webhook secret"))}
    end
  end

  def handle_event(
        "sync-tickets",
        _params,
        %{assigns: %{integration: %Integration{id: nil}}} = socket
      ) do
    {:noreply,
     put_flash(socket, :error, gettext("Save the Hi.Events integration before syncing"))}
  end

  def handle_event("sync-tickets", _params, socket) do
    if Client.configured?() do
      case HiEventsSync.enqueue(socket.assigns.integration) do
        {:ok, _job} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Ticket synchronization queued"))
           |> reload_integration()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not queue ticket synchronization"))}
      end
    else
      {:noreply,
       put_flash(socket, :error, gettext("Hi.Events sync credentials are not configured"))}
    end
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

  defp reload_integration(%{assigns: %{event: nil}} = socket), do: socket

  defp reload_integration(socket) do
    event = socket.assigns.event
    integration = HiEvents.integration_for_event(event.id)
    app_settings = EventApp.get_or_create_settings(event.id)

    socket
    |> assign(:integration, integration)
    |> assign(:app_settings, app_settings)
    |> assign(
      :app_settings_form,
      to_form(EventApp.change_settings(app_settings), as: :setting)
    )
    |> assign(:stats, HiEvents.dashboard_stats(event.id))
    |> assign(:webhook_url, url(~p"/api/integrations/hi-events/webhook"))
    |> assign(:legacy_webhook_url, url(~p"/api/integrations/hievents/events"))
    |> assign(:sync_available, Client.configured?())
    |> assign(:app_url, url(~p"/app/#{event.code}"))
    |> assign_form(HiEvents.change_integration(integration))
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :integration))
  end

  defp force_event(params, event) do
    Map.put(params, "event_id", event.id)
  end

  defp broadcast_app_settings(event) do
    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{event.uuid}",
      {:state_updated, :app_settings}
    )
  end

  def integration_saved?(%Integration{id: id}) when is_integer(id), do: true
  def integration_saved?(_integration), do: false

  def format_sync_time(nil), do: gettext("No deliveries yet")

  def format_sync_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M UTC")
  end

  def status_badge_class("processed"), do: "bg-emerald-50 text-emerald-700 ring-emerald-200"
  def status_badge_class("failed"), do: "bg-red-50 text-red-700 ring-red-200"
  def status_badge_class(_status), do: "bg-slate-100 text-slate-700 ring-slate-200"
end
