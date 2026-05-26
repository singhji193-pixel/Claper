defmodule ClaperWeb.EventLive.Bingo do
  use ClaperWeb, :live_view

  alias Claper.Bingos
  alias Claper.Bingos.BingoPlayer

  on_mount(ClaperWeb.AttendeeLiveAuth)

  @impl true
  def mount(%{"code" => code}, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    event = Claper.Events.get_event_with_code(code)

    if is_nil(event) do
      {:ok,
       socket
       |> put_flash(:error, gettext("Event doesn't exist"))
       |> redirect(to: "/")}
    else
      {:ok,
       socket
       |> assign(:page_title, gettext("Bingo"))
       |> assign(:event, event)
       |> assign(:active_tab, "play")
       |> reload_bingo()}
    end
  end

  @impl true
  def handle_event("save-player", %{"bingo_player" => player_params}, socket) do
    case Bingos.ensure_player(
           socket.assigns.event,
           socket.assigns.attendee_identifier,
           player_params
         ) do
      {:ok, _player} ->
        {:noreply,
         socket
         |> assign(:active_tab, "play")
         |> put_flash(:info, gettext("Your Bingo card is ready"))
         |> reload_bingo()}

      {:error, changeset} ->
        {:noreply, assign(socket, :player_form, to_form(changeset))}
    end
  end

  def handle_event("save-profile", %{"bingo_player" => player_params}, socket) do
    case Bingos.update_player_profile(socket.assigns.player, player_params) do
      {:ok, _player} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Profile saved"))
         |> reload_bingo()}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  def handle_event("connect", %{"connection" => %{"code" => code}}, socket) do
    connect(socket, code)
  end

  def handle_event("scan-code", %{"code" => code}, socket) do
    connect(socket, code)
  end

  def handle_event("set-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, normalize_tab(tab, socket.assigns.settings))}
  end

  def toggle_side_menu(js \\ %JS{}) do
    js
    |> JS.toggle(
      to: "#side-menu-shadow",
      out: "animate__animated animate__fadeOut",
      in: "animate__animated animate__fadeIn"
    )
    |> JS.toggle(
      to: "#side-menu",
      out: "animate__animated animate__slideOutLeft",
      in: "animate__animated animate__slideInLeft"
    )
  end

  def connection_name(%{player_id: player_id, connected_player: connected}, player_id) do
    connected.name
  end

  def connection_name(%{player: player}, _player_id), do: player.name

  def tab_button_class(tab, active_tab) do
    base =
      "shrink-0 rounded-md px-3 py-2 text-sm font-semibold transition-colors"

    if tab == active_tab do
      "#{base} bg-primary-500 text-white"
    else
      "#{base} bg-white text-gray-600 hover:bg-gray-100"
    end
  end

  def tabs(settings) do
    tabs = [
      {"play", gettext("Play")},
      {"connections", gettext("Connections")},
      {"people", gettext("People")},
      {"profile", gettext("Profile")}
    ]

    if settings && settings.leaderboard_enabled do
      tabs ++ [{"leaderboard", gettext("Leaderboard")}]
    else
      tabs
    end
  end

  def format_bingo_time(nil), do: nil

  def format_bingo_time(%NaiveDateTime{} = inserted_at) do
    Calendar.strftime(inserted_at, "%b %d, %H:%M")
  end

  defp connect(socket, code) do
    case Bingos.connect_player(socket.assigns.event.id, socket.assigns.attendee_identifier, code) do
      {:ok, connection} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Connected with %{name}", name: connection.connected_player.name)
         )
         |> assign(:active_tab, "play")
         |> reload_bingo()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, connection_error(reason))}
    end
  end

  defp reload_bingo(socket) do
    settings = Bingos.get_or_create_settings(socket.assigns.event.id)
    player = Bingos.get_player(socket.assigns.event.id, socket.assigns.attendee_identifier)
    prompts = Bingos.list_prompts(socket.assigns.event.id)
    current_prompt = Bingos.current_prompt(socket.assigns.event.id, player)
    progress_count = Bingos.progress_count(player)
    connections = Bingos.list_connections_for_player(player)
    connection_profiles = Bingos.connection_profiles_for_player(player, settings)
    forum_players = Bingos.list_forum_players(socket.assigns.event.id)

    leaderboard =
      if settings.leaderboard_enabled, do: Bingos.leaderboard(socket.assigns.event.id), else: []

    player_changeset =
      (player || %BingoPlayer{})
      |> Bingos.change_player(%{})

    profile_changeset =
      (player || %BingoPlayer{})
      |> Bingos.change_player(%{})

    socket
    |> assign(:settings, settings)
    |> assign(:prompts, prompts)
    |> assign(:player, player)
    |> assign(:current_prompt, current_prompt)
    |> assign(:progress_count, progress_count)
    |> assign(:connections, connections)
    |> assign(:connection_profiles, connection_profiles)
    |> assign(:forum_players, forum_players)
    |> assign(:leaderboard, leaderboard)
    |> assign(:player_form, to_form(player_changeset))
    |> assign(:profile_form, to_form(profile_changeset))
    |> assign(:connection_form, to_form(%{"code" => ""}, as: :connection))
  end

  defp normalize_tab("leaderboard", %{leaderboard_enabled: true}), do: "leaderboard"

  defp normalize_tab(tab, _settings) when tab in ["play", "connections", "people", "profile"],
    do: tab

  defp normalize_tab(_tab, _settings), do: "play"

  defp connection_error(:player_not_found), do: gettext("Choose your Bingo name first")
  defp connection_error(:not_found), do: gettext("No attendee found for that code")
  defp connection_error(:self_connection), do: gettext("Scan another attendee to continue")
  defp connection_error(:duplicate_connection), do: gettext("That connection is already saved")
  defp connection_error(:complete), do: gettext("You completed every Bingo prompt")
  defp connection_error(_), do: gettext("Unable to save that connection")
end
