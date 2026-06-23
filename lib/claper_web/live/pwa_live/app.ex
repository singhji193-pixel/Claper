defmodule ClaperWeb.PwaLive.App do
  use ClaperWeb, :live_view

  alias Claper.{Agendas, Bingos, EventApp, Events}
  alias Claper.Bingos.BingoPlayer
  alias Claper.EventApp.LiveInteractions
  alias Claper.Events.Event
  alias ClaperWeb.Presence

  on_mount(ClaperWeb.AttendeeLiveAuth)

  @impl true
  def mount(params, session, socket) do
    vanity = !Map.has_key?(params, "code")
    code = Map.get(params, "code") || public_event_code()

    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    attendee_session_token =
      socket.assigns[:event_app_session_token] ||
        Map.get(session, "event_app_session_token")

    case code && Events.get_event_with_code(code) do
      %Event{} = event ->
        settings = EventApp.settings_for_event(event.id)
        bootstrap = EventApp.bootstrap_for_event(event, attendee_session_token)
        interaction_key = interaction_key(event.id, attendee_session_token)
        agenda_items = Agendas.list_agenda_items(event.id)

        {:ok,
         socket
         |> assign(:page_title, ngs_page_title(socket.assigns.live_action))
         |> assign(:event, event)
         |> assign(:event_code, event.code)
         |> assign(:vanity, vanity)
         |> assign(:settings, settings)
         |> assign(:bootstrap, bootstrap)
         |> assign(:attendee, bootstrap.attendee)
         |> assign(:attendee_session_token, attendee_session_token)
         |> assign(:interaction_key, interaction_key)
         |> assign(:agenda_items, agenda_items)
         |> assign(:agenda_days, Agendas.agenda_days(event.id))
         |> assign(:agenda_tracks, Agendas.agenda_tracks(event.id))
         |> assign(:visible_agenda_items, agenda_items)
         |> assign(:agenda_query, "")
         |> assign(:agenda_saved_only, false)
         |> assign(:selected_day, nil)
         |> assign(:selected_track, "all")
         |> assign(:people_query, "")
         |> assign(:scanner_open, false)
         |> assign(:session_item, nil)
         |> assign(:session_resources, [])
         |> assign(:ticket_wallet, ticket_wallet(event.id, attendee_session_token))
         |> assign(
           :bookmarked_agenda_item_ids,
           EventApp.list_bookmarked_agenda_item_ids(event.id, attendee_session_token)
         )
         |> assign(:status, :ready)
         |> load_bingo()
         |> load_live_snapshot()
         |> maybe_connect_live()}

      nil ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Event app unavailable"))
         |> assign(:event, nil)
         |> assign(:event_code, code || "")
         |> assign(:vanity, vanity)
         |> assign(:settings, nil)
         |> assign(:bootstrap, nil)
         |> assign(:attendee, nil)
         |> assign(:attendee_session_token, nil)
         |> assign(:interaction_key, nil)
         |> assign(:agenda_items, [])
         |> assign(:agenda_days, [])
         |> assign(:agenda_tracks, [])
         |> assign(:visible_agenda_items, [])
         |> assign(:agenda_query, "")
         |> assign(:agenda_saved_only, false)
         |> assign(:selected_day, nil)
         |> assign(:selected_track, "all")
         |> assign(:people_query, "")
         |> assign(:scanner_open, false)
         |> assign(:forum_players, [])
         |> assign(:visible_forum_players, [])
         |> assign(:bingo_settings, nil)
         |> assign(:bingo_player, nil)
         |> assign(:bingo_profile_form, nil)
         |> assign(:bingo_connection_form, nil)
         |> assign(:bingo_current_prompt, nil)
         |> assign(:bingo_progress, 0)
         |> assign(:bingo_connections, [])
         |> assign(:session_item, nil)
         |> assign(:session_resources, [])
         |> assign(:ticket_wallet, nil)
         |> assign(:bookmarked_agenda_item_ids, MapSet.new())
         |> assign(:live_snapshot, nil)
         |> assign(:status, :not_found)}
    end
  end

  @impl true
  def handle_params(params, url, %{assigns: %{status: :ready}} = socket) do
    if signed_in?(socket.assigns.attendee) do
      {:noreply, apply_event_app_action(socket, socket.assigns.live_action, params)}
    else
      {:noreply, redirect(socket, to: login_redirect_path(socket.assigns, url))}
    end
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:pwa_live_snapshot, snapshot}, socket) do
    {:noreply, assign(socket, :live_snapshot, snapshot)}
  end

  def handle_info({:pwa_live_error, reason}, socket) do
    {:noreply, put_flash(socket, :error, live_error_message(reason))}
  end

  def handle_info(message, socket) do
    if LiveInteractions.invalidation_message?(message) do
      {:noreply, refresh_live_state(socket)}
    else
      {:noreply, socket}
    end
  end

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
      {:noreply, redirect(socket, to: app_path(socket.assigns, "/login"))}
    end
  end

  def handle_event("create-bingo-player", %{"bingo_player" => player_params}, socket) do
    case Bingos.ensure_player(
           socket.assigns.event,
           socket.assigns.interaction_key,
           player_params
         ) do
      {:ok, _player} ->
        {:noreply,
         socket
         |> load_bingo()
         |> put_flash(:info, gettext("Your networking card is ready."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :bingo_profile_form, to_form(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create your networking card."))}
    end
  end

  def handle_event("connect-bingo", %{"connection" => %{"code" => code}}, socket) do
    connect_bingo(socket, code)
  end

  def handle_event("scan-code", %{"code" => code}, socket) do
    connect_bingo(socket, code)
  end

  def handle_event("toggle-scanner", _params, socket) do
    {:noreply, assign(socket, :scanner_open, !socket.assigns.scanner_open)}
  end

  defp apply_event_app_action(socket, :agenda, params) do
    selected_day = selected_day(params["day"], socket.assigns.agenda_days)
    selected_track = selected_track(params["track"], socket.assigns.agenda_tracks)
    query = normalize_agenda_query(params["q"])
    saved_only = truthy_param?(params["saved"])

    socket
    |> assign(:page_title, gettext("Agenda"))
    |> assign(:selected_day, selected_day)
    |> assign(:selected_track, selected_track)
    |> assign(:agenda_query, query)
    |> assign(:agenda_saved_only, saved_only)
    |> assign(:session_item, nil)
    |> assign(
      :visible_agenda_items,
      visible_agenda_items(socket, selected_day, selected_track, query, saved_only)
    )
  end

  defp apply_event_app_action(socket, :session, %{"agenda_item_id" => agenda_item_id}) do
    session_item = Agendas.get_agenda_item_for_event(socket.assigns.event.id, agenda_item_id)

    session_resources =
      if session_item && socket.assigns.settings.resources_enabled,
        do: Agendas.list_resources(session_item.id, published_only: true),
        else: []

    selected_day = session_item && date_value(NaiveDateTime.to_date(session_item.starts_at))
    selected_track = session_item && (session_item.track_name || "all")

    socket
    |> assign(:page_title, if(session_item, do: session_item.title, else: gettext("Session")))
    |> assign(:selected_day, selected_day)
    |> assign(:selected_track, selected_track || "all")
    |> assign(:session_item, session_item)
    |> assign(:session_resources, session_resources)
    |> assign(:visible_agenda_items, socket.assigns.agenda_items)
  end

  defp apply_event_app_action(socket, :ticket, _params) do
    socket
    |> assign(:page_title, gettext("Ticket"))
    |> assign(:session_item, nil)
    |> assign(
      :ticket_wallet,
      ticket_wallet(socket.assigns.event.id, socket.assigns.attendee_session_token)
    )
  end

  defp apply_event_app_action(socket, :people, params) do
    query = normalize_people_query(params["q"])

    socket
    |> assign(:page_title, gettext("People"))
    |> assign(:people_query, query)
    |> assign(:visible_forum_players, filter_forum_players(socket.assigns.forum_players, query))
    |> assign(:session_item, nil)
  end

  defp apply_event_app_action(socket, live_action, _params) do
    socket
    |> assign(:page_title, ngs_page_title(live_action))
    |> assign(:session_item, nil)
  end

  def resource_icon("pdf"), do: "hero-document-text"
  def resource_icon("slides"), do: "hero-presentation-chart-bar"
  def resource_icon("recording"), do: "hero-play-circle"
  def resource_icon(_kind), do: "hero-link"

  defp visible_agenda_items(socket, selected_day, selected_track, query, saved_only) do
    socket.assigns.event.id
    |> Agendas.list_agenda_items_for_app(day: selected_day, track: selected_track)
    |> filter_saved_agenda_items(socket.assigns.bookmarked_agenda_item_ids, saved_only)
    |> filter_agenda_query(query)
  end

  defp filter_saved_agenda_items(items, bookmarked_ids, true) do
    Enum.filter(items, &MapSet.member?(bookmarked_ids, &1.id))
  end

  defp filter_saved_agenda_items(items, _bookmarked_ids, _saved_only), do: items

  defp filter_agenda_query(items, ""), do: items

  defp filter_agenda_query(items, query) do
    query = String.downcase(query)

    Enum.filter(items, fn item ->
      [
        item.title,
        item.description,
        item.session_type,
        item.track_name,
        item.speaker_name,
        item.speaker_title,
        item.speaker_company,
        item.location_name
      ]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.any?(&String.contains?(String.downcase(&1), query))
    end)
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

  defp load_bingo(%{assigns: %{event: %Event{} = event}} = socket) do
    settings = Bingos.get_or_create_settings(event.id)
    player = Bingos.get_player(event.id, socket.assigns.interaction_key)
    forum_players = Bingos.list_forum_players(event.id)

    profile_changeset =
      case player do
        %BingoPlayer{} = player ->
          Bingos.change_player(player)

        nil ->
          Bingos.change_player(%BingoPlayer{}, %{
            name: attendee_display_name(socket.assigns.attendee)
          })
      end

    socket
    |> assign(:bingo_settings, settings)
    |> assign(:bingo_player, player)
    |> assign(:bingo_profile_form, to_form(profile_changeset))
    |> assign(:bingo_connection_form, to_form(%{"code" => ""}, as: :connection))
    |> assign(:bingo_current_prompt, Bingos.current_prompt(event.id, player))
    |> assign(:bingo_progress, Bingos.progress_count(player))
    |> assign(:bingo_connections, Bingos.list_connections_for_player(player))
    |> assign(:forum_players, forum_players)
    |> assign(:visible_forum_players, filter_forum_players(forum_players, ""))
  end

  defp load_bingo(socket), do: socket

  defp load_live_snapshot(%{assigns: %{event: %Event{} = event}} = socket) do
    case LiveInteractions.snapshot(event, socket.assigns.interaction_key) do
      {:ok, snapshot} -> assign(socket, :live_snapshot, snapshot)
      {:error, _reason} -> assign(socket, :live_snapshot, nil)
    end
  end

  defp load_live_snapshot(socket), do: assign(socket, :live_snapshot, nil)

  defp refresh_live_state(%{assigns: %{event: %Event{} = event}} = socket) do
    socket
    |> assign(:settings, EventApp.settings_for_event(event.id))
    |> load_live_snapshot()
  end

  defp refresh_live_state(socket), do: socket

  defp maybe_connect_live(socket) do
    if connected?(socket) and is_binary(socket.assigns.interaction_key) do
      :ok = LiveInteractions.subscribe(socket.assigns.event)

      Presence.track(
        self(),
        "event:#{socket.assigns.event.uuid}",
        socket.assigns.interaction_key,
        %{source: "pwa"}
      )
    end

    socket
  end

  def active_live?(%{enabled: true, banned: false, active: active}) when not is_nil(active),
    do: true

  def active_live?(_snapshot), do: false

  defp live_error_message(:feature_disabled), do: gettext("Live interactions are not open.")
  defp live_error_message(:banned), do: gettext("Live participation is unavailable.")
  defp live_error_message(:invalid_selection), do: gettext("Select an answer before submitting.")
  defp live_error_message(:invalid_option), do: gettext("That answer is no longer available.")

  defp live_error_message(:interaction_mismatch),
    do: gettext("The presenter moved to a new interaction.")

  defp live_error_message(_reason), do: gettext("Your response could not be saved. Try again.")

  defp connect_bingo(socket, code) do
    case Bingos.connect_player(
           socket.assigns.event.id,
           socket.assigns.interaction_key,
           code
         ) do
      {:ok, connection} ->
        {:noreply,
         socket
         |> load_bingo()
         |> assign(:scanner_open, false)
         |> put_flash(
           :info,
           gettext("Connected with %{name}.",
             name: bingo_connection_name(connection, socket.assigns.bingo_player)
           )
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, bingo_connection_error(reason))}
    end
  end

  defp normalize_agenda_query(nil), do: ""

  defp normalize_agenda_query(query) when is_binary(query) do
    query |> String.trim() |> String.slice(0, 80)
  end

  defp normalize_agenda_query(_query), do: ""

  defp interaction_key(event_id, token) do
    case EventApp.interaction_identity(event_id, token) do
      {:ok, identity} -> identity.interaction_key
      {:error, _reason} -> nil
    end
  end

  defp normalize_people_query(nil), do: ""

  defp normalize_people_query(query) when is_binary(query) do
    query |> String.trim() |> String.slice(0, 80)
  end

  defp normalize_people_query(_query), do: ""

  defp filter_forum_players(players, ""), do: players

  defp filter_forum_players(players, query) do
    query = String.downcase(query)

    Enum.filter(players, fn player ->
      [player.name, player.title, player.company, player.intro]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.any?(&String.contains?(String.downcase(&1), query))
    end)
  end

  defp truthy_param?(value) when value in ["1", "true", "on", "yes"], do: true
  defp truthy_param?(_value), do: false

  def saved_agenda_count(bookmarked_ids), do: MapSet.size(bookmarked_ids)

  defp login_redirect_path(route_source, url) do
    route_source
    |> app_path("/login")
    |> append_next_param(next_path(url))
  end

  defp next_path(url) do
    case URI.parse(url) do
      %URI{path: path, query: nil} when is_binary(path) -> path
      %URI{path: path, query: query} when is_binary(path) -> "#{path}?#{query}"
      _ -> nil
    end
  end

  defp append_next_param(path, nil), do: path
  defp append_next_param(path, ""), do: path

  defp append_next_param(path, next) do
    separator = if String.contains?(path, "?"), do: "&", else: "?"
    path <> separator <> URI.encode_query(next: next)
  end

  def agenda_filter_path(route_source, day, track, query, saved_only) do
    params =
      %{}
      |> maybe_put_param(:day, day)
      |> maybe_put_param(:track, track)
      |> maybe_put_param(:q, normalize_agenda_query(query))
      |> maybe_put_param(:saved, if(saved_only, do: "1", else: nil))

    path = app_path(route_source, "/agenda")

    if params == %{} do
      path
    else
      path <> "?" <> URI.encode_query(params)
    end
  end

  def app_path(route_source, suffix \\ "")

  def app_path(%{vanity: true}, suffix), do: public_app_path(suffix)

  def app_path(%{event: %Event{code: code}}, suffix), do: coded_app_path(code, suffix)

  def app_path(%{event_code: code}, suffix), do: coded_app_path(code, suffix)

  def app_path(%Event{code: code}, suffix), do: coded_app_path(code, suffix)

  def app_path(code, suffix) when is_binary(code), do: coded_app_path(code, suffix)

  def app_path(_route_source, suffix), do: public_app_path(suffix)

  defp public_event_code do
    :claper
    |> Application.get_env(:event_app, [])
    |> Keyword.get(:public_event_code)
    |> case do
      code when is_binary(code) -> String.trim(code)
      _ -> nil
    end
    |> case do
      "" -> nil
      code -> code
    end
  end

  defp public_app_path(""), do: "/"
  defp public_app_path("/"), do: "/"
  defp public_app_path(suffix) when is_binary(suffix), do: suffix

  defp coded_app_path(code, ""), do: "/app/#{code}"
  defp coded_app_path(code, "/"), do: "/app/#{code}"
  defp coded_app_path(code, suffix), do: "/app/#{code}#{suffix}"

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, :track, "all"), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  def track_tone(track) when is_binary(track) do
    case rem(:erlang.phash2(track), 4) do
      0 -> "ai"
      1 -> "growth"
      2 -> "capital"
      _ -> "future"
    end
  end

  def attendee_initials(attendee) do
    attendee
    |> attendee_display_name()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
    |> case do
      "" -> "NG"
      initials -> initials
    end
  end

  def next_agenda_item(items) do
    now = NaiveDateTime.utc_now()

    Enum.find(items, fn item ->
      agenda_item_live?(item, now) or
        (match?(%NaiveDateTime{}, item.starts_at) and
           NaiveDateTime.compare(item.starts_at, now) in [:gt, :eq])
    end)
  end

  def agenda_item_live?(item), do: agenda_item_live?(item, NaiveDateTime.utc_now())

  defp agenda_item_live?(%{starts_at: %NaiveDateTime{} = starts_at} = item, now) do
    duration = item.duration_minutes || 60
    ends_at = NaiveDateTime.add(starts_at, duration, :minute)

    NaiveDateTime.compare(starts_at, now) in [:lt, :eq] and
      NaiveDateTime.compare(ends_at, now) == :gt
  end

  defp agenda_item_live?(_item, _now), do: false
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

  def ngs_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.8"
      stroke="currentColor"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["ngs-svg-icon", @class]}
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
        <% "hero-magnifying-glass" -> %>
          <path d="m20 20-4.25-4.25" />
          <path d="M17.25 10.75a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0Z" />
        <% "hero-arrow-right" -> %>
          <path d="M4.5 12h15M14.5 7l5 5-5 5" />
        <% "hero-camera" -> %>
          <path d="M5.75 7.25h2l1.25-2h6l1.25 2h2A1.75 1.75 0 0 1 20 9v7.25A1.75 1.75 0 0 1 18.25 18H5.75A1.75 1.75 0 0 1 4 16.25V9a1.75 1.75 0 0 1 1.75-1.75Z" />
          <path d="M15.5 12.25a3.5 3.5 0 1 1-7 0 3.5 3.5 0 0 1 7 0Z" />
        <% "hero-lock-closed" -> %>
          <path d="M6.5 10h11A1.5 1.5 0 0 1 19 11.5v7A1.5 1.5 0 0 1 17.5 20h-11A1.5 1.5 0 0 1 5 18.5v-7A1.5 1.5 0 0 1 6.5 10Z" />
          <path d="M8.25 10V7.75a3.75 3.75 0 0 1 7.5 0V10M12 14v2" />
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
  attr :variant, :string, default: "bottom"
  attr :center, :boolean, default: false

  def ngs_nav_item(assigns) do
    assigns =
      assign(
        assigns,
        :classes,
        ngs_nav_item_classes(assigns.variant, assigns.active, assigns.center)
      )

    ~H"""
    <.link navigate={@navigate} aria-current={@active && "page"} class={@classes}>
      <.ngs_icon name={@icon} class="size-5" />
      <span>{@label}</span>
    </.link>
    """
  end

  defp ngs_nav_item_classes("sidebar", active, _center) do
    ["ngs-sidebar-item ngs-focus", active && "is-active"]
  end

  defp ngs_nav_item_classes(_variant, active, true) do
    ["ngs-nav-fab ngs-focus", active && "is-active"]
  end

  defp ngs_nav_item_classes(_variant, active, _center) do
    ["ngs-nav-item ngs-focus", active && "is-active"]
  end

  attr :event, :map, required: true
  attr :vanity, :boolean, default: false
  attr :day, :any, required: true
  attr :selected_day, :string, default: nil
  attr :agenda_query, :string, default: ""
  attr :agenda_saved_only, :boolean, default: false

  def ngs_day_chip(assigns) do
    assigns = assign(assigns, :day_value, date_value(assigns.day))

    ~H"""
    <.link
      patch={agenda_filter_path(assigns, @day_value, "all", @agenda_query, @agenda_saved_only)}
      class={[
        "ngs-day ngs-focus",
        @selected_day == @day_value && "is-active"
      ]}
    >
      <span class="ngs-day-dow">{format_agenda_day_short(@day)}</span>
      <strong class="ngs-day-num">{format_agenda_day_number(@day)}</strong>
    </.link>
    """
  end

  attr :event, :map, required: true
  attr :vanity, :boolean, default: false
  attr :track, :string, required: true
  attr :selected_day, :string, default: nil
  attr :selected_track, :string, default: "all"
  attr :agenda_query, :string, default: ""
  attr :agenda_saved_only, :boolean, default: false

  def ngs_track_chip(assigns) do
    ~H"""
    <.link
      patch={agenda_filter_path(assigns, @selected_day, @track, @agenda_query, @agenda_saved_only)}
      class={[
        "ngs-chip ngs-focus",
        @selected_track == @track && "is-active"
      ]}
    >
      <span>{track_label(@track)}</span>
    </.link>
    """
  end

  attr :event, :map, required: true
  attr :vanity, :boolean, default: false
  attr :item, :map, required: true
  attr :saved, :boolean, default: false
  attr :signed_in, :boolean, default: false

  def ngs_agenda_card(assigns) do
    assigns =
      assign(
        assigns,
        :track_tone,
        track_tone(assigns.item.track_name || assigns.item.session_type || "all")
      )

    ~H"""
    <article class={["ngs-schedule-slot", "ngs-track-#{@track_tone}"]}>
      <div class="ngs-slot-time" aria-hidden="true">
        <time>{format_agenda_time(@item.starts_at)}</time>
        <span>{format_duration(@item.duration_minutes)}</span>
      </div>

      <div class={["ngs-session-card", @saved && "is-saved"]}>
        <div class="ngs-session-topline">
          <span :if={@item.session_type || @item.track_name} class="ngs-track-tag">
            {session_kicker(@item)}
          </span>
          <button
            type="button"
            phx-click="toggle-agenda-bookmark"
            phx-value-id={@item.id}
            class={["ngs-save-button ngs-focus", @saved && "is-active"]}
            aria-pressed={@saved}
            aria-label={save_label(@saved, @signed_in)}
          >
            <.ngs_icon
              name={if @saved, do: "hero-check-circle", else: "hero-bookmark"}
              class="size-4"
            />
            <span class="sr-only">{save_label(@saved, @signed_in)}</span>
          </button>
        </div>

        <.link navigate={app_path(assigns, "/agenda/#{@item.id}")} class="ngs-session-title ngs-focus">
          {@item.title}
        </.link>

        <p :if={@item.speaker_name} class="ngs-session-speaker">
          {speaker_line(@item)}
        </p>

        <div class="ngs-session-meta">
          <span :if={@item.location_name}>
            <.ngs_icon name="hero-map-pin" class="size-4" />
            {@item.location_name}
          </span>
          <span>
            <.ngs_icon name="hero-clock" class="size-4" />
            {format_session_date(@item.starts_at)}
          </span>
        </div>
      </div>
    </article>
    """
  end

  attr :event, :map, required: true
  attr :wallet, :map, required: true

  def ngs_ticket_wallet_card(assigns) do
    ~H"""
    <section class="ngs-pass-card" aria-label={gettext("Event ticket")}>
      <div class="ngs-pass-band"></div>
      <div class="ngs-pass-head">
        <div>
          <p class="ngs-eyebrow">{gettext("NextGen Summit")}</p>
          <h2>{@wallet.ticket_name || gettext("Verified ticket")}</h2>
        </div>
        <span class="ngs-badge ngs-badge-ok">
          <.ngs_icon name="hero-check-circle" class="size-4" />
          {ticket_status_label(@wallet)}
        </span>
      </div>

      <div class="ngs-pass-holder">
        <span>{gettext("Attendee")}</span>
        <strong>{@wallet.attendee_name}</strong>
        <small>{@wallet.attendee_email}</small>
      </div>

      <div class="ngs-pass-perf" aria-hidden="true"><span></span></div>

      <div class="ngs-pass-code-row">
        <div
          id="pwa-ticket-qr"
          phx-hook="QRCode"
          phx-update="ignore"
          data-url={@wallet.external_ticket_id || @wallet.external_attendee_id || @wallet.reference}
          data-size="152"
          class="ngs-qr-mark ngs-real-qr"
          aria-label={gettext("Ticket QR code")}
        >
        </div>
        <div class="ngs-pass-reference">
          <span>{gettext("Reference")}</span>
          <strong>{@wallet.reference}</strong>
          <div class="ngs-barcode" aria-hidden="true">
            <i></i><i class="s"></i><i></i><i></i><i class="s"></i><i></i><i class="w"></i><i></i><i class="s"></i><i></i>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def ngs_theme_style(%{primary_color: primary, accent_color: accent}) do
    primary = safe_hex_color(primary, "#f15a24")
    accent = safe_hex_color(accent, "#365a91")

    "--ngs-primary: #{primary}; --ngs-accent: #{accent};"
  end

  def ngs_theme_style(_settings), do: ""

  defp safe_hex_color(value, fallback) when is_binary(value) do
    if Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value), do: value, else: fallback
  end

  defp safe_hex_color(_value, fallback), do: fallback

  def ngs_page_title(:agenda), do: gettext("Agenda")
  def ngs_page_title(:session), do: gettext("Session")
  def ngs_page_title(:people), do: gettext("People")
  def ngs_page_title(:scan), do: gettext("Scan")
  def ngs_page_title(:bingo), do: gettext("Bingo")
  def ngs_page_title(:ticket), do: gettext("Ticket")
  def ngs_page_title(:profile), do: gettext("Profile")
  def ngs_page_title(:live), do: gettext("Live")
  def ngs_page_title(_), do: gettext("Event app")

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

  def format_agenda_day_short(%Date{} = day) do
    Calendar.strftime(day, "%a")
  end

  def format_agenda_day_number(%Date{} = day) do
    Calendar.strftime(day, "%d")
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

  def forum_player_role(player) do
    [player.title, player.company]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" at ")
  end

  def format_bingo_connection_time(nil), do: ""

  def format_bingo_connection_time(%NaiveDateTime{} = inserted_at) do
    Calendar.strftime(inserted_at, "%b %d")
  end

  def ticket_status_label(%{checked_in: true}), do: gettext("Checked in")

  def ticket_status_label(%{status: status}) when is_binary(status),
    do: status |> String.replace("_", " ") |> String.capitalize()

  def ticket_status_label(_wallet), do: gettext("Verified")

  def ticket_status_icon(%{checked_in: true}), do: "hero-check-circle"
  def ticket_status_icon(_wallet), do: "hero-ticket"

  def bingo_connection_name(connection, %BingoPlayer{id: player_id}) do
    if connection.player_id == player_id do
      connection.connected_player.name
    else
      connection.player.name
    end
  end

  def bingo_connection_name(_connection, _player), do: gettext("attendee")

  def bingo_connection_error(:not_found), do: gettext("That attendee code was not found.")
  def bingo_connection_error(:self_connection), do: gettext("You cannot connect with yourself.")

  def bingo_connection_error(:duplicate_connection),
    do: gettext("You already used this connection for the current prompt.")

  def bingo_connection_error(:complete), do: gettext("You have completed every Bingo prompt.")

  def bingo_connection_error(:player_not_found),
    do: gettext("Create your networking card before connecting.")

  def bingo_connection_error(_reason), do: gettext("Could not save this connection.")

  def save_label(true, _signed_in), do: gettext("Saved")
  def save_label(false, true), do: gettext("Save")
  def save_label(false, false), do: gettext("Sign in to save")

  def saved_agenda_item?(bookmarked_ids, item) do
    MapSet.member?(bookmarked_ids, item.id)
  end

  def event_status(%Event{} = event, agenda_items) do
    cond do
      Enum.any?(agenda_items, &agenda_item_live?/1) -> gettext("Live now")
      next_agenda_item(agenda_items) -> gettext("Upcoming")
      !Enum.empty?(agenda_items) -> gettext("Agenda complete")
      true -> event_status(event)
    end
  end

  def event_live?(agenda_items), do: Enum.any?(agenda_items, &agenda_item_live?/1)

  def event_status_icon(agenda_items) do
    if next_agenda_item(agenda_items), do: "hero-clock", else: "hero-check-circle"
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
