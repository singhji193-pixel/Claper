defmodule ClaperWeb.PwaLive.App do
  use ClaperWeb, :live_view

  alias Claper.{Agendas, EventApp, Events}
  alias Claper.Events.Event

  on_mount(ClaperWeb.AttendeeLiveAuth)

  @impl true
  def mount(%{"code" => code}, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    attendee_identifier =
      socket.assigns[:attendee_identifier] || Map.get(session, "attendee_identifier")

    case Events.get_event_with_code(code) do
      %Event{} = event ->
        settings = EventApp.settings_for_event(event.id)

        {:ok,
         socket
         |> assign(:page_title, pwa_page_title(socket.assigns.live_action))
         |> assign(:event, event)
         |> assign(:event_code, event.code)
         |> assign(:settings, settings)
         |> assign(:bootstrap, EventApp.bootstrap_for_event(event, attendee_identifier))
         |> assign(:agenda_items, Agendas.list_agenda_items(event.id))
         |> assign(:status, :ready)}

      nil ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Event app unavailable"))
         |> assign(:event, nil)
         |> assign(:event_code, code)
         |> assign(:settings, nil)
         |> assign(:bootstrap, nil)
         |> assign(:agenda_items, [])
         |> assign(:status, :not_found)}
    end
  end

  attr :name, :string, required: true
  attr :class, :string, default: "size-5"

  def pwa_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.8"
      stroke="currentColor"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["pwa-svg-icon", @class]}
      aria-hidden="true"
    >
      <%= case @name do %>
        <% "hero-home" -> %>
          <path d="M3.75 11.25 12 4.5l8.25 6.75" />
          <path d="M5.25 10.5v8.25h4.5v-4.5h4.5v4.5h4.5V10.5" />
        <% "hero-calendar-days" -> %>
          <path d="M7 3.75v2.5M17 3.75v2.5M4.75 8.5h14.5" />
          <path d="M5.75 5.75h12.5a1.5 1.5 0 0 1 1.5 1.5v10.5a1.5 1.5 0 0 1-1.5 1.5H5.75a1.5 1.5 0 0 1-1.5-1.5V7.25a1.5 1.5 0 0 1 1.5-1.5Z" />
          <path d="M8 12h.01M12 12h.01M16 12h.01M8 15.5h.01M12 15.5h.01" />
        <% "hero-list-bullet" -> %>
          <path d="M8 6.5h12M8 12h12M8 17.5h12" />
          <path d="M4 6.5h.01M4 12h.01M4 17.5h.01" />
        <% "hero-qr-code" -> %>
          <path d="M4.5 4.5h5v5h-5zM14.5 4.5h5v5h-5zM4.5 14.5h5v5h-5z" />
          <path d="M14.5 14.5h2v2h-2zM18.5 14.5h1v5h-5v-1M14.5 18.5h1" />
        <% "hero-user-group" -> %>
          <path d="M9.5 11.25a3.25 3.25 0 1 0 0-6.5 3.25 3.25 0 0 0 0 6.5ZM4.25 19.25a5.25 5.25 0 0 1 10.5 0" />
          <path d="M16.25 10.75a2.75 2.75 0 1 0-1.25-5.2M15.75 14.25a4.25 4.25 0 0 1 4 5" />
        <% "hero-user-circle" -> %>
          <path d="M12 13a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z" />
          <path d="M5.75 19.25a7 7 0 0 1 12.5 0" />
          <path d="M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
        <% "hero-chevron-right" -> %>
          <path d="m9 5.5 6.5 6.5L9 18.5" />
        <% "hero-exclamation-triangle" -> %>
          <path d="M11.1 4.25 3.35 18a1.5 1.5 0 0 0 1.3 2.25h14.7a1.5 1.5 0 0 0 1.3-2.25L12.9 4.25a1.03 1.03 0 0 0-1.8 0Z" />
          <path d="M12 9v4M12 17h.01" />
        <% "hero-arrow-top-right-on-square" -> %>
          <path d="M13.5 4.5h6v6M19.5 4.5 10.5 13.5" />
          <path d="M11.5 6.5H6.25a1.75 1.75 0 0 0-1.75 1.75v9.5c0 .97.78 1.75 1.75 1.75h9.5c.97 0 1.75-.78 1.75-1.75V12.5" />
        <% _ -> %>
          <path d="M12 5v14M5 12h14" />
      <% end %>
    </svg>
    """
  end

  attr :active, :boolean, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :navigate, :string, required: true

  def nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      aria-current={@active && "page"}
      class={[
        "pwa-tab pwa-focus",
        @active && "pwa-tab-active",
        !@active && "pwa-tab-inactive"
      ]}
    >
      <.pwa_icon name={@icon} class="size-5" />
      <span>{@label}</span>
    </.link>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :tone, :string, default: "primary"

  def stat_pill(assigns) do
    ~H"""
    <div class={["pwa-stat-pill", "pwa-stat-pill-#{@tone}"]}>
      <.pwa_icon name={@icon} class="size-5" />
      <div>
        <p>{@value}</p>
        <span>{@label}</span>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :meta, :string, default: nil

  def feature_action(assigns) do
    assigns =
      assign(assigns, :class, [
        "pwa-feature-action pwa-focus",
        assigns.disabled && "pwa-feature-action-disabled"
      ])

    cond do
      assigns.disabled ->
        ~H"""
        <div class={@class} aria-disabled="true">
          <.feature_action_content icon={@icon} title={@title} description={@description} meta={@meta} />
        </div>
        """

      assigns.navigate ->
        ~H"""
        <.link navigate={@navigate} class={@class}>
          <.feature_action_content icon={@icon} title={@title} description={@description} meta={@meta} />
        </.link>
        """

      true ->
        ~H"""
        <a href={@href} class={@class}>
          <.feature_action_content icon={@icon} title={@title} description={@description} meta={@meta} />
        </a>
        """
    end
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true
  attr :meta, :string, default: nil

  defp feature_action_content(assigns) do
    ~H"""
    <span class="pwa-feature-icon">
      <.pwa_icon name={@icon} class="size-5" />
    </span>
    <span class="min-w-0">
      <strong>{@title}</strong>
      <small>{@description}</small>
      <em :if={@meta}>{@meta}</em>
    </span>
    <.pwa_icon name="hero-chevron-right" class="size-5 shrink-0 text-slate-400" />
    """
  end

  def pwa_theme_style(%{primary_color: primary, accent_color: accent}) do
    primary = safe_hex_color(primary, "#f15a24")
    accent = safe_hex_color(accent, "#365a91")

    "--pwa-primary: #{primary}; --pwa-accent: #{accent};"
  end

  def pwa_theme_style(_settings), do: ""

  defp safe_hex_color(value, fallback) when is_binary(value) do
    if Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value), do: value, else: fallback
  end

  defp safe_hex_color(_value, fallback), do: fallback

  def pwa_page_title(:agenda), do: gettext("Agenda")
  def pwa_page_title(:people), do: gettext("People")
  def pwa_page_title(:bingo), do: gettext("Bingo")
  def pwa_page_title(:profile), do: gettext("Profile")
  def pwa_page_title(_), do: gettext("Event app")

  def format_event_time(nil), do: gettext("Time to be announced")

  def format_event_time(%NaiveDateTime{} = starts_at) do
    Calendar.strftime(starts_at, "%b %d, %Y at %H:%M")
  end

  def format_agenda_time(%NaiveDateTime{} = starts_at) do
    Calendar.strftime(starts_at, "%H:%M")
  end

  def format_duration(nil), do: gettext("Session")
  def format_duration(minutes), do: gettext("%{count} min", count: minutes)

  def event_status(%Event{} = event) do
    cond do
      Event.finished?(event) -> gettext("Finished")
      Event.started?(event) -> gettext("Live now")
      true -> gettext("Upcoming")
    end
  end

  def feature_count(%{count: count}, singular, _plural) when count == 1, do: "1 #{singular}"
  def feature_count(%{count: count}, _singular, plural), do: "#{count} #{plural}"
end
