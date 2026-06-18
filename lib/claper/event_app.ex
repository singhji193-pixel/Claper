defmodule Claper.EventApp do
  @moduledoc """
  Event companion app settings and bootstrap helpers.
  """

  import Ecto.Query, warn: false

  alias Claper.{Agendas, Bingos, Events, HiEvents, Repo}
  alias Claper.EventApp.{AgendaBookmark, Attendee, Notifications, OtpChallenge, Session, Setting}
  alias Claper.Events.Event
  alias Claper.HiEvents.EventTicket

  @otp_ttl_seconds 10 * 60
  @otp_rate_limit_window_seconds 15 * 60
  @otp_rate_limit_count 5
  @otp_min_request_spacing_seconds 60
  @otp_max_attempts 5
  @session_ttl_seconds 30 * 24 * 60 * 60

  def get_settings(event_id), do: Repo.get_by(Setting, event_id: event_id)

  def settings_for_event(event_id) do
    get_settings(event_id) || %Setting{event_id: event_id}
  end

  def get_or_create_settings(event_id) do
    case get_settings(event_id) do
      %Setting{} = setting ->
        setting

      nil ->
        %Setting{}
        |> Setting.changeset(%{event_id: event_id})
        |> Repo.insert!(
          on_conflict: :nothing,
          conflict_target: :event_id
        )

        get_settings(event_id)
    end
  end

  def change_settings(%Setting{} = setting, attrs \\ %{}) do
    Setting.changeset(setting, attrs)
  end

  def bootstrap_event(code, attendee_session_token \\ nil) do
    case Events.get_event_with_code(code) do
      %Event{} = event -> {:ok, bootstrap_for_event(event, attendee_session_token)}
      nil -> {:error, :not_found}
    end
  end

  def bootstrap_for_event(%Event{} = event, attendee_session_token \\ nil) do
    agenda_items = Agendas.list_agenda_items(event.id)
    bingo_prompts = Bingos.list_prompts(event.id)
    ticket_count = HiEvents.ticket_count(event.id)
    settings = settings_for_event(event.id)
    attendee = attendee_from_session_token(event.id, attendee_session_token)

    %{
      event: public_event(event),
      settings: Setting.public(settings),
      features: %{
        agenda: feature("Agenda", true, length(agenda_items), "/app/#{event.code}/agenda"),
        bingo: feature("Bingo", true, length(bingo_prompts), "/app/#{event.code}/bingo"),
        people: feature("People", settings.people_enabled, 0, "/app/#{event.code}/people"),
        ticket:
          feature("Ticket", settings.ticket_enabled, ticket_count, "/app/#{event.code}/ticket"),
        chat: feature("Chat", settings.chat_enabled, 0, "/app/#{event.code}/chat"),
        sponsors: feature("Sponsors", settings.sponsors_enabled, 0, "/app/#{event.code}/sponsors")
      },
      attendee: public_attendee(attendee, attendee_session_token)
    }
  end

  def request_login_code(event_code, email, opts \\ []) do
    with {:ok, event} <- fetch_event(event_code),
         {:ok, normalized_email} <- normalize_login_email(email),
         {:ok, ticket} <- fetch_ticket(event.id, normalized_email),
         :ok <- check_otp_rate_limit(event.id, normalized_email) do
      code = Keyword.get(opts, :code) || generate_otp_code()
      now = now()

      attrs = %{
        event_id: event.id,
        email: normalized_email,
        code_hash: otp_hash(event.id, normalized_email, code),
        status: "pending",
        attempts_count: 0,
        max_attempts: @otp_max_attempts,
        expires_at: DateTime.add(now, @otp_ttl_seconds, :second),
        request_ip: option(opts, :request_ip),
        user_agent: option(opts, :user_agent)
      }

      with {:ok, challenge} <- %OtpChallenge{} |> OtpChallenge.changeset(attrs) |> Repo.insert(),
           {:ok, challenge} <- deliver_login_code(event, ticket, challenge, code) do
        {:ok,
         %{
           event: event,
           ticket: ticket,
           challenge: challenge,
           delivery_status: challenge.delivery_status
         }}
      end
    end
  end

  def verify_login_code(event_code, email, code, opts \\ []) do
    with {:ok, event} <- fetch_event(event_code),
         {:ok, normalized_email} <- normalize_login_email(email),
         {:ok, ticket} <- fetch_ticket(event.id, normalized_email),
         {:ok, challenge} <- latest_login_challenge(event.id, normalized_email),
         :ok <- verify_challenge_state(challenge),
         :ok <- verify_challenge_code(challenge, event.id, normalized_email, code),
         {:ok, attendee} <- upsert_attendee(event, ticket),
         {:ok, session, token} <- create_attendee_session(event, attendee, opts),
         {:ok, _challenge} <- mark_challenge_verified(challenge) do
      {:ok, %{event: event, attendee: attendee, session: session, token: token}}
    end
  end

  def get_attendee_by_session_token(event_id, token) do
    case attendee_session(event_id, token) do
      {:ok, %Session{attendee: attendee}} -> {:ok, attendee}
      {:error, reason} -> {:error, reason}
    end
  end

  def ticket_wallet(event_id, token) do
    case attendee_session(event_id, token) do
      {:ok, %Session{attendee: attendee}} ->
        {:ok, attendee |> Repo.preload(:hi_events_ticket) |> public_ticket_wallet()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_bookmarked_agenda_item_ids(event_id, token) do
    case attendee_session(event_id, token) do
      {:ok, %Session{attendee: attendee}} ->
        AgendaBookmark
        |> where([b], b.event_id == ^event_id and b.event_app_attendee_id == ^attendee.id)
        |> select([b], b.agenda_item_id)
        |> Repo.all()
        |> MapSet.new()

      {:error, _reason} ->
        MapSet.new()
    end
  end

  def toggle_agenda_bookmark(event_id, token, agenda_item_id) do
    with {:ok, %Session{attendee: attendee}} <- attendee_session(event_id, token),
         {:ok, agenda_item_id} <- fetch_agenda_item_id(event_id, agenda_item_id) do
      case get_agenda_bookmark(event_id, attendee.id, agenda_item_id) do
        %AgendaBookmark{} = bookmark ->
          case Repo.delete(bookmark) do
            {:ok, _bookmark} -> {:ok, :removed}
            {:error, changeset} -> {:error, changeset}
          end

        nil ->
          %AgendaBookmark{}
          |> AgendaBookmark.changeset(%{
            event_id: event_id,
            event_app_attendee_id: attendee.id,
            agenda_item_id: agenda_item_id
          })
          |> Repo.insert()
          |> case do
            {:ok, _bookmark} -> {:ok, :saved}
            {:error, changeset} -> {:error, changeset}
          end
      end
    end
  end

  def sign_out_attendee_session(token) when is_binary(token) do
    token_hash = token_hash(token)

    Session
    |> where([s], s.token_hash == ^token_hash)
    |> Repo.delete_all()

    :ok
  end

  def sign_out_attendee_session(_token), do: :ok

  defp feature(label, enabled, count, href) do
    %{
      label: label,
      enabled: enabled,
      available: enabled and count > 0,
      count: count,
      href: href
    }
  end

  defp public_event(%Event{} = event) do
    %{
      id: event.id,
      uuid: event.uuid,
      code: event.code,
      name: event.name,
      started_at: format_time(event.started_at),
      expired_at: format_time(event.expired_at)
    }
  end

  defp format_time(nil), do: nil
  defp format_time(%NaiveDateTime{} = time), do: NaiveDateTime.to_iso8601(time)

  defp fetch_event(code) do
    case Events.get_event_with_code(code) do
      %Event{} = event -> {:ok, event}
      nil -> {:error, :event_not_found}
    end
  end

  defp normalize_login_email(email) when is_binary(email) do
    email =
      email
      |> String.trim()
      |> String.downcase()

    if Regex.match?(~r/^[^\s]+@[^\s]+$/, email) do
      {:ok, email}
    else
      {:error, :invalid_email}
    end
  end

  defp normalize_login_email(_email), do: {:error, :invalid_email}

  defp fetch_ticket(event_id, email) do
    case HiEvents.get_ticket_by_event_and_email(event_id, email) do
      %EventTicket{} = ticket -> {:ok, ticket}
      nil -> {:error, :ticket_not_found}
    end
  end

  defp check_otp_rate_limit(event_id, email) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    window_start = NaiveDateTime.add(now, -@otp_rate_limit_window_seconds, :second)
    spacing_start = NaiveDateTime.add(now, -@otp_min_request_spacing_seconds, :second)

    recent_count =
      OtpChallenge
      |> where([c], c.event_id == ^event_id and c.email == ^email)
      |> where([c], c.inserted_at >= ^window_start)
      |> Repo.aggregate(:count)

    too_recent? =
      OtpChallenge
      |> where([c], c.event_id == ^event_id and c.email == ^email)
      |> where([c], c.inserted_at >= ^spacing_start)
      |> Repo.exists?()

    cond do
      recent_count >= @otp_rate_limit_count -> {:error, :too_many_requests}
      too_recent? -> {:error, :too_soon}
      true -> :ok
    end
  end

  defp deliver_login_code(event, ticket, challenge, code) do
    case Notifications.deliver_attendee_otp(%{
           event: event,
           ticket: ticket,
           challenge: challenge,
           code: code
         }) do
      {:ok, :sent} ->
        update_challenge_delivery(challenge, %{
          status: "sent",
          delivery_status: "sent",
          sent_at: now()
        })

      {:ok, :disabled} ->
        update_challenge_delivery(challenge, %{delivery_status: "disabled"})

      {:error, reason} ->
        update_challenge_delivery(challenge, %{
          delivery_status: "failed",
          delivery_error: String.slice(to_string(reason), 0, 1_000)
        })
    end
  end

  defp update_challenge_delivery(challenge, attrs) do
    challenge
    |> OtpChallenge.status_changeset(attrs)
    |> Repo.update()
  end

  defp latest_login_challenge(event_id, email) do
    challenge =
      OtpChallenge
      |> where([c], c.event_id == ^event_id and c.email == ^email)
      |> where([c], c.status in ["pending", "sent"])
      |> order_by([c], desc: c.id)
      |> limit(1)
      |> Repo.one()

    case challenge do
      %OtpChallenge{} = challenge -> {:ok, challenge}
      nil -> {:error, :code_not_requested}
    end
  end

  defp verify_challenge_state(%OtpChallenge{} = challenge) do
    cond do
      DateTime.compare(challenge.expires_at, now()) == :lt ->
        challenge
        |> OtpChallenge.status_changeset(%{status: "expired"})
        |> Repo.update()

        {:error, :code_expired}

      challenge.attempts_count >= challenge.max_attempts ->
        challenge
        |> OtpChallenge.status_changeset(%{status: "locked"})
        |> Repo.update()

        {:error, :too_many_attempts}

      true ->
        :ok
    end
  end

  defp verify_challenge_code(challenge, event_id, email, code) do
    normalized_code = normalize_otp_code(code)

    if normalized_code && otp_hash(event_id, email, normalized_code) == challenge.code_hash do
      :ok
    else
      attempts_count = challenge.attempts_count + 1
      status = if attempts_count >= challenge.max_attempts, do: "locked", else: challenge.status

      challenge
      |> OtpChallenge.status_changeset(%{attempts_count: attempts_count, status: status})
      |> Repo.update()

      if status == "locked", do: {:error, :too_many_attempts}, else: {:error, :invalid_code}
    end
  end

  defp upsert_attendee(%Event{} = event, %EventTicket{} = ticket) do
    email = ticket.attendee_email
    now = now()

    attrs = %{
      event_id: event.id,
      hi_events_ticket_id: ticket.id,
      email: email,
      name:
        ticket.attendee_name || join_name(ticket.attendee_first_name, ticket.attendee_last_name),
      first_name: ticket.attendee_first_name,
      last_name: ticket.attendee_last_name,
      ticket_name: ticket.ticket_name,
      verified_at: now,
      last_seen_at: now
    }

    case Repo.get_by(Attendee, event_id: event.id, email: email) do
      nil ->
        %Attendee{}
        |> Attendee.changeset(attrs)
        |> Repo.insert()

      %Attendee{} = attendee ->
        attendee
        |> Attendee.changeset(attrs)
        |> Repo.update()
    end
  end

  defp create_attendee_session(%Event{} = event, %Attendee{} = attendee, opts) do
    token = generate_session_token()
    now = now()

    attrs = %{
      event_id: event.id,
      event_app_attendee_id: attendee.id,
      token_hash: token_hash(token),
      expires_at: DateTime.add(now, @session_ttl_seconds, :second),
      last_seen_at: now,
      user_agent: option(opts, :user_agent)
    }

    case %Session{} |> Session.changeset(attrs) |> Repo.insert() do
      {:ok, session} -> {:ok, session, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp mark_challenge_verified(challenge) do
    challenge
    |> OtpChallenge.status_changeset(%{status: "verified", consumed_at: now()})
    |> Repo.update()
  end

  defp attendee_from_session_token(event_id, token) do
    case get_attendee_by_session_token(event_id, token) do
      {:ok, attendee} -> attendee
      {:error, _reason} -> nil
    end
  end

  defp attendee_session(_event_id, token) when not is_binary(token),
    do: {:error, :not_authenticated}

  defp attendee_session(_event_id, ""), do: {:error, :not_authenticated}

  defp attendee_session(event_id, token) do
    session =
      Session
      |> where([s], s.event_id == ^event_id and s.token_hash == ^token_hash(token))
      |> where([s], s.expires_at > ^now())
      |> preload(:attendee)
      |> Repo.one()

    case session do
      %Session{} = session ->
        session
        |> Session.touch_changeset(%{last_seen_at: now()})
        |> Repo.update()

        {:ok, session}

      nil ->
        {:error, :not_authenticated}
    end
  end

  defp public_attendee(nil, token) do
    %{
      authenticated: false,
      identifier_present: is_binary(token) and byte_size(token) > 0,
      email: nil,
      name: nil,
      ticket_name: nil
    }
  end

  defp public_attendee(%Attendee{} = attendee, _token) do
    %{
      authenticated: true,
      identifier_present: true,
      id: attendee.id,
      email: attendee.email,
      name: attendee.name,
      first_name: attendee.first_name,
      last_name: attendee.last_name,
      ticket_name: attendee.ticket_name,
      verified_at: format_datetime(attendee.verified_at)
    }
  end

  defp public_ticket_wallet(%Attendee{hi_events_ticket: %EventTicket{} = ticket} = attendee) do
    %{
      attendee_name: attendee.name || ticket.attendee_name || attendee.email,
      attendee_email: attendee.email,
      ticket_name: attendee.ticket_name || ticket.ticket_name,
      status: ticket.status,
      checked_in: ticket.status == "checked_in" or not is_nil(ticket.checked_in_at),
      checked_in_at: format_datetime(ticket.checked_in_at),
      reference: ticket_reference(ticket),
      external_ticket_id: ticket.external_ticket_id,
      external_attendee_id: ticket.external_attendee_id
    }
  end

  defp public_ticket_wallet(%Attendee{} = attendee) do
    %{
      attendee_name: attendee.name || attendee.email,
      attendee_email: attendee.email,
      ticket_name: attendee.ticket_name,
      status: "verified",
      checked_in: false,
      checked_in_at: nil,
      reference: "ATT-#{attendee.id}",
      external_ticket_id: nil,
      external_attendee_id: nil
    }
  end

  defp ticket_reference(%EventTicket{} = ticket) do
    cond do
      present?(ticket.external_ticket_id) -> ticket.external_ticket_id
      present?(ticket.external_attendee_id) -> ticket.external_attendee_id
      true -> "TICKET-#{ticket.id}"
    end
  end

  defp fetch_agenda_item_id(event_id, agenda_item_id) do
    case Agendas.get_agenda_item_for_event(event_id, agenda_item_id) do
      %{id: id} -> {:ok, id}
      nil -> {:error, :agenda_item_not_found}
    end
  end

  defp get_agenda_bookmark(event_id, attendee_id, agenda_item_id) do
    Repo.get_by(AgendaBookmark,
      event_id: event_id,
      event_app_attendee_id: attendee_id,
      agenda_item_id: agenda_item_id
    )
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp generate_otp_code do
    :crypto.strong_rand_bytes(4)
    |> :binary.decode_unsigned()
    |> rem(10_000)
    |> Integer.to_string()
    |> String.pad_leading(4, "0")
  end

  defp normalize_otp_code(code) when is_binary(code) do
    code =
      code
      |> String.replace(~r/\D/, "")
      |> String.slice(0, 4)

    if String.length(code) == 4, do: code
  end

  defp normalize_otp_code(_code), do: nil

  defp otp_hash(event_id, email, code) do
    body = "#{event_id}:#{email}:#{code}"

    :crypto.mac(:hmac, :sha256, otp_secret(), body)
    |> Base.encode16(case: :lower)
  end

  defp token_hash(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end

  defp otp_secret do
    config = Application.get_env(:claper, :event_app, [])

    Keyword.get(config, :otp_secret) ||
      Keyword.get(Application.get_env(:claper, ClaperWeb.Endpoint, []), :secret_key_base) ||
      "event-app-local-secret"
  end

  defp generate_session_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  defp option(opts, key) when is_list(opts), do: Keyword.get(opts, key)

  defp option(opts, key) when is_map(opts),
    do: Map.get(opts, key) || Map.get(opts, to_string(key))

  defp option(_opts, _key), do: nil

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp join_name(nil, nil), do: nil
  defp join_name(first_name, nil), do: first_name
  defp join_name(nil, last_name), do: last_name
  defp join_name(first_name, last_name), do: "#{first_name} #{last_name}"
end
