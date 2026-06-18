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

    attendee_session_token =
      socket.assigns[:event_app_session_token] ||
        Map.get(session, "event_app_session_token") ||
        socket.assigns[:attendee_identifier] ||
        Map.get(session, "attendee_identifier")

    case Events.get_event_with_code(code) do
      %Event{} = event ->
        settings = EventApp.settings_for_event(event.id)
        bootstrap = EventApp.bootstrap_for_event(event, attendee_session_token)
        agenda_items = Agendas.list_agenda_items(event.id)

        {:ok,
         socket
         |> assign(:page_title, pwa_page_title(socket.assigns.live_action))
         |> assign(:event, event)
         |> assign(:event_code, event.code)
         |> assign(:settings, settings)
         |> assign(:bootstrap, bootstrap)
         |> assign(:attendee, bootstrap.attendee)
         |> assign(:attendee_session_token, attendee_session_token)
         |> assign(:agenda_items, agenda_items)
         |> assign(:agenda_days, Agendas.agenda_days(event.id))
         |> assign(:agenda_tracks, Agendas.agenda_tracks(event.id))
         |> assign(:visible_agenda_items, agenda_items)
         |> assign(:selected_day, nil)
         |> assign(:selected_track, "all")
         |> assign(:session_item, nil)
         |> assign(:ticket_wallet, ticket_wallet(event.id, attendee_session_token))
         |> assign(
           :bookmarked_agenda_item_ids,
           EventApp.list_bookmarked_agenda_item_ids(event.id, attendee_session_token)
         )
         |> assign(:status, :ready)}

      nil ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Event app unavailable"))
         |> assign(:event, nil)
         |> assign(:event_code, code)
         |> assign(:settings, nil)
         |> assign(:bootstrap, nil)
         |> assign(:attendee, nil)
         |> assign(:attendee_session_token, nil)
         |> assign(:agenda_items, [])
         |> assign(:agenda_days, [])
         |> assign(:agenda_tracks, [])
         |> assign(:visible_agenda_items, [])
         |> assign(:selected_day, nil)
         |> assign(:selected_track, "all")
         |> assign(:session_item, nil)
         |> assign(:ticket_wallet, nil)
         |> assign(:bookmarked_agenda_item_ids, MapSet.new())
         |> assign(:status, :not_found)}
    end
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{status: :ready}} = socket) do
    {:noreply, apply_pwa_action(socket, socket.assigns.live_action, params)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle-agenda-bookmark", %{"id" => id}, socket) do
    if signed_in?(socket.assigns.attendee) do
      case EventApp.toggle_agenda_bookmark(
             socket.assigns.event.id,
             socket.assigns.attendee_session_token,
             id
           ) do
        {:ok, :saved} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Session saved."))
           |> refresh_bookmarked_agenda_items()}

        {:ok, :removed} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Session removed."))
           |> refresh_bookmarked_agenda_items()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update this session."))}
      end
    else
      {:noreply, redirect(socket, to: ~p"/app/#{socket.assigns.event.code}/login")}
    end
  end

  defp apply_pwa_action(socket, :agenda, params) do
    selected_day = selected_day(params["day"], socket.assigns.agenda_days)
    selected_track = selected_track(params["track"], socket.assigns.agenda_tracks)

    socket
    |> assign(:page_title, gettext("Agenda"))
    |> assign(:selected_day, selected_day)
    |> assign(:selected_track, selected_track)
    |> assign(:session_item, nil)
    |> assign(:visible_agenda_items, visible_agenda_items(socket, selected_day, selected_track))
  end

  defp apply_pwa_action(socket, :session, %{"agenda_item_id" => agenda_item_id}) do
    session_item = Agendas.get_agenda_item_for_event(socket.assigns.event.id, agenda_item_id)
    selected_day = session_item && date_value(NaiveDateTime.to_date(session_item.starts_at))
    selected_track = session_item && (session_item.track_name || "all")

    socket
    |> assign(:page_title, if(session_item, do: session_item.title, else: gettext("Session")))
    |> assign(:selected_day, selected_day)
    |> assign(:selected_track, selected_track || "all")
    |> assign(:session_item, session_item)
    |> assign(:visible_agenda_items, socket.assigns.agenda_items)
  end

  defp apply_pwa_action(socket, :ticket, _params) do
    socket
    |> assign(:page_title, gettext("Ticket"))
    |> assign(:session_item, nil)
    |> assign(
      :ticket_wallet,
      ticket_wallet(socket.assigns.event.id, socket.assigns.attendee_session_token)
    )
  end

  defp apply_pwa_action(socket, live_action, _params) do
    socket
    |> assign(:page_title, pwa_page_title(live_action))
    |> assign(:session_item, nil)
  end

  defp visible_agenda_items(socket, selected_day, selected_track) do
    Agendas.list_agenda_items_for_app(socket.assigns.event.id,
      day: selected_day,
      track: selected_track
    )
  end

  defp refresh_bookmarked_agenda_items(socket) do
    assign(
      socket,
      :bookmarked_agenda_item_ids,
      EventApp.list_bookmarked_agenda_item_ids(
        socket.assigns.event.id,
        socket.assigns.attendee_session_token
      )
    )
  end

  defp ticket_wallet(event_id, attendee_session_token) do
    case EventApp.ticket_wallet(event_id, attendee_session_token) do
      {:ok, wallet} -> wallet
      {:error, _reason} -> nil
    end
  end

  defp selected_day(nil, [first_day | _days]), do: date_value(first_day)
  defp selected_day("", [first_day | _days]), do: date_value(first_day)
  defp selected_day(_day, []), do: nil

  defp selected_day(day, agenda_days) when is_binary(day) do
    if Enum.any?(agenda_days, &(date_value(&1) == day)),
      do: day,
      else: selected_day(nil, agenda_days)
  end

  defp selected_track(nil, _tracks), do: "all"
  defp selected_track("", _tracks), do: "all"
  defp selected_track("all", _tracks), do: "all"

  defp selected_track(track, tracks) when is_binary(track) do
    if track in tracks, do: track, else: "all"
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
        <% "hero-ticket" -> %>
          <path d="M4.75 7.25A1.75 1.75 0 0 1 6.5 5.5h11a1.75 1.75 0 0 1 1.75 1.75v2.2a2.55 2.55 0 0 0 0 5.1v2.2a1.75 1.75 0 0 1-1.75 1.75h-11a1.75 1.75 0 0 1-1.75-1.75v-2.2a2.55 2.55 0 0 0 0-5.1v-2.2Z" />
          <path d="M9.5 8.75v6.5M14.5 8.75v6.5" />
        <% "hero-identification" -> %>
          <path d="M6 5h12a1.75 1.75 0 0 1 1.75 1.75v10.5A1.75 1.75 0 0 1 18 19H6a1.75 1.75 0 0 1-1.75-1.75V6.75A1.75 1.75 0 0 1 6 5Z" />
          <path d="M8 9.75h4.25M8 13h3.25M15.25 10.25h1.5M14.5 13.75h3" />
        <% "hero-map-pin" -> %>
          <path d="M17.25 10.25c0 4.25-5.25 8.75-5.25 8.75s-5.25-4.5-5.25-8.75a5.25 5.25 0 1 1 10.5 0Z" />
          <path d="M12 10.25a1.75 1.75 0 1 0 0-3.5 1.75 1.75 0 0 0 0 3.5Z" />
        <% "hero-clock" -> %>
          <path d="M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
          <path d="M12 7.5V12l3 2" />
        <% "hero-bookmark" -> %>
          <path d="M7 4.75h10A1.25 1.25 0 0 1 18.25 6v13.25L12 15.5l-6.25 3.75V6A1.25 1.25 0 0 1 7 4.75Z" />
        <% "hero-check-circle" -> %>
          <path d="M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
          <path d="m8.75 12.25 2.25 2.25 4.5-5" />
        <% "hero-tag" -> %>
          <path d="M4.75 6.75v5.4c0 .47.19.91.51 1.24l5.35 5.35a1.75 1.75 0 0 0 2.48 0l5.65-5.65a1.75 1.75 0 0 0 0-2.48L13.39 5.26a1.75 1.75 0 0 0-1.24-.51h-5.4a2 2 0 0 0-2 2Z" />
          <path d="M8.75 8.75h.01" />
        <% "hero-envelope" -> %>
          <path d="M5.75 6.5h12.5A1.75 1.75 0 0 1 20 8.25v7.5a1.75 1.75 0 0 1-1.75 1.75H5.75A1.75 1.75 0 0 1 4 15.75v-7.5A1.75 1.75 0 0 1 5.75 6.5Z" />
          <path d="m5 8 7 5 7-5" />
        <% "hero-arrow-right-on-rectangle" -> %>
          <path d="M9.75 8.75V6.5A1.75 1.75 0 0 1 11.5 4.75h5A1.75 1.75 0 0 1 18.25 6.5v11a1.75 1.75 0 0 1-1.75 1.75h-5a1.75 1.75 0 0 1-1.75-1.75v-2.25" />
          <path d="M4.75 12h8.5M10.5 9.25 13.25 12 10.5 14.75" />
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

  attr :event, :map, required: true
  attr :day, :any, required: true
  attr :selected_day, :string, default: nil

  def day_chip(assigns) do
    assigns = assign(assigns, :day_value, date_value(assigns.day))

    ~H"""
    <.link
      patch={~p"/app/#{@event.code}/agenda?day=#{@day_value}&track=all"}
      class={[
        "pwa-filter-chip pwa-focus",
        @selected_day == @day_value && "pwa-filter-chip-active"
      ]}
    >
      <span>{format_agenda_day(@day)}</span>
    </.link>
    """
  end

  attr :event, :map, required: true
  attr :track, :string, required: true
  attr :selected_day, :string, default: nil
  attr :selected_track, :string, default: "all"

  def track_chip(assigns) do
    ~H"""
    <.link
      patch={~p"/app/#{@event.code}/agenda?day=#{@selected_day}&track=#{@track}"}
      class={[
        "pwa-filter-chip pwa-focus",
        @selected_track == @track && "pwa-filter-chip-active"
      ]}
    >
      <span>{track_label(@track)}</span>
    </.link>
    """
  end

  attr :event, :map, required: true
  attr :item, :map, required: true
  attr :saved, :boolean, default: false
  attr :signed_in, :boolean, default: false

  def agenda_card(assigns) do
    ~H"""
    <article class="pwa-session-card">
      <div class="pwa-session-time">
        <time>{format_agenda_time(@item.starts_at)}</time>
        <span>{format_duration(@item.duration_minutes)}</span>
      </div>

      <div class="pwa-session-body">
        <div class="pwa-session-heading">
          <p :if={@item.session_type || @item.track_name} class="pwa-session-kicker">
            {session_kicker(@item)}
          </p>
          <.link
            navigate={~p"/app/#{@event.code}/agenda/#{@item.id}"}
            class="pwa-session-title pwa-focus"
          >
            {@item.title}
          </.link>
        </div>

        <p :if={@item.speaker_name} class="pwa-session-speaker">
          {speaker_line(@item)}
        </p>

        <div class="pwa-session-meta">
          <span :if={@item.location_name}>
            <.pwa_icon name="hero-map-pin" class="size-4" />
            {@item.location_name}
          </span>
          <span>
            <.pwa_icon name="hero-clock" class="size-4" />
            {format_session_date(@item.starts_at)}
          </span>
        </div>

        <p :if={@item.description} class="pwa-session-description">
          {String.slice(@item.description, 0, 160)}
        </p>
      </div>

      <button
        type="button"
        phx-click="toggle-agenda-bookmark"
        phx-value-id={@item.id}
        class={[
          "pwa-save-button pwa-focus",
          @saved && "pwa-save-button-active"
        ]}
        aria-pressed={@saved}
      >
        <.pwa_icon name={if @saved, do: "hero-check-circle", else: "hero-bookmark"} class="size-5" />
        <span>{save_label(@saved, @signed_in)}</span>
      </button>
    </article>
    """
  end

  attr :event, :map, required: true
  attr :wallet, :map, required: true

  def ticket_wallet_card(assigns) do
    ~H"""
    <section class="pwa-ticket-card">
      <div class="pwa-ticket-header">
        <span class="pwa-ticket-icon">
          <.pwa_icon name="hero-ticket" class="size-7" />
        </span>
        <div>
          <p class="pwa-eyebrow">{gettext("Event pass")}</p>
          <h3>{@wallet.ticket_name || gettext("Verified ticket")}</h3>
        </div>
      </div>

      <div class="pwa-ticket-holder">
        <p>{@wallet.attendee_name}</p>
        <span>{@wallet.attendee_email}</span>
      </div>

      <div class="pwa-ticket-code" aria-label={gettext("Ticket reference")}>
        <span>{gettext("Reference")}</span>
        <strong>{@wallet.reference}</strong>
      </div>

      <dl class="pwa-ticket-details">
        <div>
          <dt>{gettext("Event")}</dt>
          <dd>{@event.name}</dd>
        </div>
        <div>
          <dt>{gettext("Status")}</dt>
          <dd>{ticket_status_label(@wallet)}</dd>
        </div>
      </dl>
    </section>
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
  def pwa_page_title(:session), do: gettext("Session")
  def pwa_page_title(:people), do: gettext("People")
  def pwa_page_title(:bingo), do: gettext("Bingo")
  def pwa_page_title(:ticket), do: gettext("Ticket")
  def pwa_page_title(:profile), do: gettext("Profile")
  def pwa_page_title(_), do: gettext("Event app")

  def format_event_time(nil), do: gettext("Time to be announced")

  def format_event_time(%NaiveDateTime{} = starts_at) do
    Calendar.strftime(starts_at, "%b %d, %Y at %H:%M")
  end

  def format_agenda_time(%NaiveDateTime{} = starts_at) do
    Calendar.strftime(starts_at, "%H:%M")
  end

  def format_session_date(%NaiveDateTime{} = starts_at) do
    Calendar.strftime(starts_at, "%b %d")
  end

  def format_agenda_day(%Date{} = day) do
    Calendar.strftime(day, "%b %d")
  end

  def date_value(%Date{} = day), do: Date.to_iso8601(day)

  def format_duration(nil), do: gettext("Session")
  def format_duration(minutes), do: gettext("%{count} min", count: minutes)

  def track_label("all"), do: gettext("All tracks")
  def track_label(track), do: track

  def session_kicker(item) do
    [item.session_type, item.track_name]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" / ")
  end

  def speaker_line(item) do
    detail =
      [item.speaker_title, item.speaker_company]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(", ")

    if detail == "", do: item.speaker_name, else: "#{item.speaker_name} - #{detail}"
  end

  def ticket_status_label(%{checked_in: true}), do: gettext("Checked in")

  def ticket_status_label(%{status: status}) when is_binary(status),
    do: status |> String.replace("_", " ") |> String.capitalize()

  def ticket_status_label(_wallet), do: gettext("Verified")

  def save_label(true, _signed_in), do: gettext("Saved")
  def save_label(false, true), do: gettext("Save")
  def save_label(false, false), do: gettext("Sign in to save")

  def saved_agenda_item?(bookmarked_ids, item) do
    MapSet.member?(bookmarked_ids, item.id)
  end

  def event_status(%Event{} = event) do
    cond do
      Event.finished?(event) -> gettext("Finished")
      Event.started?(event) -> gettext("Live now")
      true -> gettext("Upcoming")
    end
  end

  def feature_count(%{count: count}, singular, _plural) when count == 1, do: "1 #{singular}"
  def feature_count(%{count: count}, _singular, plural), do: "#{count} #{plural}"

  def signed_in?(%{authenticated: true}), do: true
  def signed_in?(_attendee), do: false

  def attendee_display_name(%{name: name}) when is_binary(name) and name != "", do: name
  def attendee_display_name(%{email: email}) when is_binary(email), do: email
  def attendee_display_name(_attendee), do: gettext("Attendee")
end
