defmodule ClaperWeb.EventLive.Agenda do
  use ClaperWeb, :live_view

  alias Claper.Agendas

  @headroom_portrait_names [
    "Brittany Michalchuk",
    "Jasmeen Kaur Judge",
    "Prashant Agrawal",
    "Prashant Agrawal (Mr. P)",
    "Navdha Sharma",
    "Suhana Gaba",
    "Pankaj Bagga"
  ]

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

  def agenda_chapter_label(nil), do: nil
  def agenda_chapter_label(""), do: nil

  def agenda_chapter_label(track_name) do
    case track_name |> String.trim() |> String.downcase() do
      "morning catalyst" -> gettext("The Morning Catalyst")
      "the morning catalyst" -> gettext("The Morning Catalyst")
      "the crucible" -> gettext("The Crucible")
      "midday" -> gettext("Midday")
      "afternoon" -> gettext("Afternoon Programming")
      "afternoon programming" -> gettext("Afternoon Programming")
      "the hot seat" -> gettext("The Hot Seat")
      "verdict & close" -> gettext("The Verdict & Close")
      "the verdict & close" -> gettext("The Verdict & Close")
      _ -> track_name
    end
  end

  def headroom_portrait?(name) when is_binary(name), do: name in @headroom_portrait_names
  def headroom_portrait?(_name), do: false

  def emcee_profiles do
    [
      %{
        name: "Badhri Narayanan",
        role: gettext("Morning Catalyst"),
        image_url: "https://nextgensummit.co/speakers/badhri-narayanan.jpg",
        linkedin_url: "https://ca.linkedin.com/in/badhri-narayanan"
      },
      %{
        name: "Brittany Michalchuk",
        role: gettext("Afternoon Spark"),
        image_url: "https://nextgensummit.co/speakers/brittany-michalchuk.jpg",
        linkedin_url: "https://ca.linkedin.com/in/brittanymichalchuk"
      }
    ]
  end

  def agenda_moment(title) when is_binary(title) do
    normalized_title = title |> String.trim() |> String.downcase()

    cond do
      String.contains?(normalized_title, "registration") ->
        %{
          kind: "registration",
          label: gettext("Check in, connect, and grab a coffee")
        }

      String.contains?(normalized_title, "mastermind lunch") ->
        %{
          kind: "mastermind-lunch",
          label: gettext("Ideas shared over lunch")
        }

      String.contains?(normalized_title, "networking break") or
          String.contains?(normalized_title, "brainstorm break") ->
        %{
          kind: "networking-break",
          label: gettext("Recharge between sessions")
        }

      String.contains?(normalized_title, "honour awards") or
          String.contains?(normalized_title, "under 30") ->
        %{
          kind: "nextgen-honouree",
          label: gettext("Celebrating the 2026 honourees")
        }

      String.contains?(normalized_title, "pitch winner") ->
        %{
          kind: "pitch-winner",
          label: gettext("The winning pitch is revealed")
        }

      String.contains?(normalized_title, "networking reception") ->
        %{
          kind: "networking-reception",
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

  def speaker_profile_link(%{name: name, linkedin_url: url}) do
    case Claper.Agendas.AgendaItem.profile_link_kind(url) do
      :linkedin ->
        %{
          url: url,
          kind: "linkedin",
          label: gettext("Find %{name} on LinkedIn", name: name)
        }

      :website ->
        %{
          url: url,
          kind: "website",
          label: gettext("Visit %{name}'s website", name: name)
        }

      nil ->
        nil
    end
  end

  def speaker_role(%{title: title}, %{name: name})
      when is_binary(title) and is_binary(name) do
    normalized_title = String.downcase(title)

    cond do
      name == "Suhana Gaba" and String.contains?(normalized_title, "own the future") ->
        %{kind: "moderator", label: gettext("Moderator"), featured: true}

      name == "Beata Jirava" and
          (String.contains?(normalized_title, "building & funding great companies") or
             String.contains?(normalized_title, "the crucible")) ->
        %{kind: "moderator", label: gettext("Moderator"), featured: true}

      name == "Nazreen Mohammed" and String.contains?(normalized_title, "the crucible") ->
        %{kind: "pitch-opener", label: gettext("Pitch opener"), featured: true}

      true ->
        nil
    end
  end

  def speaker_role(_agenda_item, _profile), do: nil
end
