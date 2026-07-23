defmodule ClaperWeb.EventLive.Agenda do
  use ClaperWeb, :live_view

  alias Claper.Agendas

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
       |> assign(:page_title, gettext("Agenda"))
       |> assign(:event, event)
       |> assign(:timezone, Claper.EventApp.event_timezone(event.id))
       |> assign(:agenda_items, Agendas.list_agenda_items(event.id))}
    end
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

  def format_agenda_time(%NaiveDateTime{} = starts_at, timezone) do
    starts_at
    |> Claper.EventApp.Time.to_local(timezone)
    |> Calendar.strftime("%b %d, %H:%M")
  end

  def format_duration(nil), do: nil
  def format_duration(minutes), do: gettext("%{count} min", count: minutes)

  def agenda_moment(title) when is_binary(title) do
    normalized_title = title |> String.trim() |> String.downcase()

    cond do
      String.contains?(normalized_title, "registration") ->
        %{
          kind: "registration",
          eyebrow: gettext("Welcome"),
          label: gettext("Check in, connect, and grab a coffee")
        }

      String.contains?(normalized_title, "networking break") or
          String.contains?(normalized_title, "brainstorm break") ->
        %{
          kind: "networking-break",
          eyebrow: gettext("Connect"),
          label: gettext("Recharge between sessions")
        }

      String.contains?(normalized_title, "under 30") ->
        %{
          kind: "under-30-awards",
          eyebrow: gettext("Recognition"),
          label: gettext("Celebrating rising leaders")
        }

      String.contains?(normalized_title, "pitch winner") ->
        %{
          kind: "pitch-winner",
          eyebrow: gettext("Finale"),
          label: gettext("The winning pitch is revealed")
        }

      String.contains?(normalized_title, "networking reception") ->
        %{
          kind: "networking-reception",
          eyebrow: gettext("Reception"),
          label: gettext("Continue the conversation")
        }

      true ->
        nil
    end
  end

  def agenda_moment(_title), do: nil

  def speaker_detail(agenda_item) do
    [agenda_item.speaker_title, agenda_item.speaker_company]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(", ")
  end
end
