defmodule Claper.Bingos do
  @moduledoc """
  The Bingos context.
  """

  import Ecto.Query, warn: false

  alias Claper.Bingos.{BingoConnection, BingoPlayer, BingoPrompt, BingoSetting}
  alias Claper.Repo

  @code_length 6
  @max_code_attempts 8
  @shared_profile_fields [
    {:title, :share_title},
    {:company, :share_company},
    {:intro, :share_intro},
    {:email, :share_email},
    {:phone, :share_phone},
    {:linkedin_url, :share_linkedin_url},
    {:website_url, :share_website_url}
  ]

  @doc """
  Returns ordered Bingo prompts for an event.
  """
  def list_prompts(nil), do: []

  def list_prompts(event_id) do
    from(p in BingoPrompt,
      where: p.event_id == ^event_id,
      order_by: [asc: p.position, asc: p.id]
    )
    |> Repo.all()
  end

  def get_prompt!(id, preload \\ []),
    do: Repo.get!(BingoPrompt, id) |> Repo.preload(preload)

  def get_prompt_for_event!(event_id, id) do
    from(p in BingoPrompt, where: p.event_id == ^event_id and p.id == ^id)
    |> Repo.one!()
  end

  def change_prompt(%BingoPrompt{} = prompt, attrs \\ %{}) do
    BingoPrompt.changeset(prompt, attrs)
  end

  def create_prompt(attrs \\ %{}) do
    Repo.transaction(fn ->
      attrs = put_create_position(attrs)

      %BingoPrompt{}
      |> BingoPrompt.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, prompt} ->
          normalize_positions(prompt.event_id)
          prompt

        {:error, changeset} ->
          Repo.rollback(%{changeset | action: :insert})
      end
    end)
  end

  def update_prompt(%BingoPrompt{} = prompt, attrs) do
    Repo.transaction(fn ->
      old_event_id = prompt.event_id
      attrs = maybe_put_moved_position(attrs, old_event_id)

      prompt
      |> BingoPrompt.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, prompt} ->
          normalize_positions(old_event_id)
          normalize_positions(prompt.event_id)
          prompt

        {:error, changeset} ->
          Repo.rollback(%{changeset | action: :update})
      end
    end)
  end

  def delete_prompt(%BingoPrompt{} = prompt) do
    Repo.transaction(fn ->
      event_id = prompt.event_id

      case Repo.delete(prompt) do
        {:ok, prompt} ->
          normalize_positions(event_id)
          prompt

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def move_prompt(event_id, prompt_id, direction) when direction in [:up, :down] do
    Repo.transaction(fn ->
      normalize_positions(event_id)
      prompts = list_prompts(event_id)
      current_index = Enum.find_index(prompts, &("#{&1.id}" == "#{prompt_id}"))

      if is_nil(current_index) do
        Repo.rollback(:not_found)
      else
        target_index = target_index(current_index, direction)

        cond do
          target_index < 0 or target_index >= length(prompts) ->
            prompts

          true ->
            current = Enum.at(prompts, current_index)
            target = Enum.at(prompts, target_index)

            current
            |> Ecto.Changeset.change(position: target.position)
            |> Repo.update!()

            target
            |> Ecto.Changeset.change(position: current.position)
            |> Repo.update!()

            normalize_positions(event_id)
        end
      end
    end)
  end

  def move_prompt(_event_id, _prompt_id, _direction), do: {:error, :invalid_direction}

  def next_position(nil), do: 0

  def next_position(event_id) do
    from(p in BingoPrompt,
      where: p.event_id == ^event_id,
      select: max(p.position)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      position -> position + 1
    end
  end

  def normalize_positions(nil), do: []

  def normalize_positions(event_id) do
    event_id
    |> list_prompts()
    |> Enum.with_index()
    |> Enum.each(fn {prompt, position} ->
      if prompt.position != position do
        prompt
        |> Ecto.Changeset.change(position: position)
        |> Repo.update!()
      end
    end)

    list_prompts(event_id)
  end

  @doc """
  Gets event Bingo settings, creating the default row when needed.
  """
  def get_or_create_settings(nil), do: nil

  def get_or_create_settings(event_id) do
    case Repo.get_by(BingoSetting, event_id: event_id) do
      %BingoSetting{} = settings ->
        settings

      nil ->
        %BingoSetting{}
        |> BingoSetting.changeset(%{event_id: event_id})
        |> Repo.insert()
        |> case do
          {:ok, settings} -> settings
          {:error, _changeset} -> Repo.get_by!(BingoSetting, event_id: event_id)
        end
    end
  end

  def change_settings(%BingoSetting{} = settings, attrs \\ %{}) do
    BingoSetting.changeset(settings, attrs)
  end

  def update_settings(%BingoSetting{} = settings, attrs) do
    settings
    |> BingoSetting.changeset(attrs)
    |> Repo.update()
  end

  def update_settings(event_id, attrs) when is_integer(event_id) or is_binary(event_id) do
    event_id
    |> get_or_create_settings()
    |> update_settings(attrs)
  end

  def get_player(event_id, attendee_identifier) do
    Repo.get_by(BingoPlayer, event_id: event_id, attendee_identifier: attendee_identifier)
  end

  def list_players(nil), do: []

  def list_players(event_id) do
    from(p in BingoPlayer,
      where: p.event_id == ^event_id,
      order_by: [asc: p.name, asc: p.id]
    )
    |> Repo.all()
  end

  def get_player_by_code(event_id, code) do
    Repo.get_by(BingoPlayer, event_id: event_id, code: normalize_code(code))
  end

  def change_player(%BingoPlayer{} = player, attrs \\ %{}) do
    BingoPlayer.changeset(player, attrs)
  end

  def ensure_player(event, attendee_identifier, attrs \\ %{}) do
    case get_player(event.id, attendee_identifier) do
      nil ->
        create_player(
          attrs
          |> put_attr(:event_id, event.id)
          |> put_attr(:attendee_identifier, attendee_identifier)
        )

      %BingoPlayer{} = player ->
        player
        |> BingoPlayer.profile_changeset(attrs)
        |> Repo.update()
    end
  end

  def update_player_profile(%BingoPlayer{} = player, attrs) do
    player
    |> BingoPlayer.profile_changeset(attrs)
    |> Repo.update()
  end

  def create_player(attrs \\ %{}, attempts \\ @max_code_attempts)

  def create_player(_attrs, 0), do: {:error, :code_generation_failed}

  def create_player(attrs, attempts) do
    attrs = put_attr(attrs, :code, attrs |> attr(:code) |> normalize_code() || generate_code())

    %BingoPlayer{}
    |> BingoPlayer.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, player} ->
        {:ok, player}

      {:error, changeset} when attempts > 1 ->
        if unique_code_error?(changeset) do
          attrs
          |> delete_attr(:code)
          |> create_player(attempts - 1)
        else
          {:error, changeset}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def current_prompt(event_id, nil), do: event_id |> list_prompts() |> List.first()

  def current_prompt(event_id, %BingoPlayer{} = player) do
    event_id
    |> list_prompts()
    |> Enum.at(progress_count(player))
  end

  def progress_count(nil), do: 0

  def progress_count(%BingoPlayer{} = player) do
    from(c in BingoConnection, where: c.player_id == ^player.id)
    |> Repo.aggregate(:count, :id)
  end

  def list_connections_for_player(nil), do: []

  def list_connections_for_player(%BingoPlayer{} = player) do
    from(c in BingoConnection,
      where: c.player_id == ^player.id or c.connected_player_id == ^player.id,
      order_by: [desc: c.id],
      preload: [:prompt, :player, :connected_player]
    )
    |> Repo.all()
  end

  def connection_profiles_for_player(player, settings \\ nil)

  def connection_profiles_for_player(nil, _settings), do: []

  def connection_profiles_for_player(%BingoPlayer{} = player, settings) do
    settings = settings || get_or_create_settings(player.event_id)

    player
    |> list_connections_for_player()
    |> Enum.map(fn connection ->
      connected_player = connected_player_for(connection, player.id)

      %{
        connection_id: connection.id,
        prompt: connection.prompt.prompt,
        connected_at: connection.inserted_at,
        profile: shared_profile(connected_player, settings)
      }
    end)
  end

  def list_forum_players(nil), do: []

  def list_forum_players(event_id) do
    settings = get_or_create_settings(event_id)

    if settings.forum_enabled do
      event_id
      |> list_players()
      |> Enum.map(&forum_profile/1)
    else
      []
    end
  end

  def shared_profile(nil, _settings), do: %{}

  def shared_profile(%BingoPlayer{} = player, nil) do
    shared_profile(player, get_or_create_settings(player.event_id))
  end

  def shared_profile(%BingoPlayer{} = player, %BingoSetting{contact_sharing_enabled: false}) do
    base_profile(player)
  end

  def shared_profile(%BingoPlayer{} = player, %BingoSetting{} = _settings) do
    Enum.reduce(@shared_profile_fields, base_profile(player), fn {field, share_field}, profile ->
      value = Map.get(player, field)

      if Map.get(player, share_field) && present?(value) do
        Map.put(profile, field, value)
      else
        profile
      end
    end)
  end

  def connect_player(event_id, attendee_identifier, raw_code) do
    with {:player, %BingoPlayer{} = player} <-
           {:player, get_player(event_id, attendee_identifier)},
         {:connected_player, %BingoPlayer{} = connected_player} <-
           {:connected_player, get_player_by_code(event_id, raw_code)},
         {:self, false} <- {:self, player.id == connected_player.id},
         {:prompt, %BingoPrompt{} = prompt} <- {:prompt, current_prompt(event_id, player)} do
      create_connection(event_id, prompt, player, connected_player)
    else
      {:player, nil} -> {:error, :player_not_found}
      {:connected_player, nil} -> {:error, :not_found}
      {:self, true} -> {:error, :self_connection}
      {:prompt, nil} -> {:error, :complete}
    end
  end

  def completed?(event_id, %BingoPlayer{} = player) do
    progress_count(player) >= length(list_prompts(event_id))
  end

  def leaderboard(nil), do: []

  def leaderboard(event_id) do
    prompt_count = length(list_prompts(event_id))

    event_id
    |> list_players()
    |> Enum.map(fn player ->
      completed_prompts = progress_count(player)

      %{
        player_id: player.id,
        name: player.name,
        completed_prompts: completed_prompts,
        total_prompts: prompt_count,
        completed?: prompt_count > 0 and completed_prompts >= prompt_count
      }
    end)
    |> Enum.sort_by(fn row -> {-row.completed_prompts, String.downcase(row.name || "")} end)
  end

  def dashboard_stats(nil) do
    %{
      player_count: 0,
      prompt_count: 0,
      connection_count: 0,
      completed_count: 0,
      completion_rate: 0,
      prompt_performance: []
    }
  end

  def dashboard_stats(event_id) do
    prompts = list_prompts(event_id)
    players = list_players(event_id)
    prompt_count = length(prompts)
    player_count = length(players)

    completed_count =
      if prompt_count == 0 do
        0
      else
        Enum.count(players, &(progress_count(&1) >= prompt_count))
      end

    %{
      player_count: player_count,
      prompt_count: prompt_count,
      connection_count: count_connections(event_id),
      completed_count: completed_count,
      completion_rate: percentage(completed_count, player_count),
      prompt_performance: prompt_performance(prompts)
    }
  end

  def export_players_rows(event_id) do
    settings = get_or_create_settings(event_id)
    prompt_count = length(list_prompts(event_id))

    headers = [
      "Name",
      "Title",
      "Company",
      "Intro",
      "Email",
      "Phone",
      "LinkedIn",
      "Website",
      "Code",
      "Connections",
      "Completed prompts",
      "Total prompts",
      "Joined at (UTC)"
    ]

    rows =
      event_id
      |> list_players()
      |> Enum.map(fn player ->
        profile = shared_profile(player, settings)

        [
          player.name,
          Map.get(profile, :title, ""),
          Map.get(profile, :company, ""),
          Map.get(profile, :intro, ""),
          Map.get(profile, :email, ""),
          Map.get(profile, :phone, ""),
          Map.get(profile, :linkedin_url, ""),
          Map.get(profile, :website_url, ""),
          player.code,
          player |> list_connections_for_player() |> length(),
          progress_count(player),
          prompt_count,
          format_naive_datetime(player.inserted_at)
        ]
      end)

    {headers, rows}
  end

  defp create_connection(event_id, prompt, player, connected_player) do
    attrs = %{
      event_id: event_id,
      bingo_prompt_id: prompt.id,
      player_id: player.id,
      connected_player_id: connected_player.id,
      pair_key: pair_key(player.id, connected_player.id)
    }

    %BingoConnection{}
    |> BingoConnection.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, connection} ->
        {:ok, Repo.preload(connection, [:prompt, :player, :connected_player])}

      {:error, changeset} ->
        if duplicate_connection_error?(changeset) do
          {:error, :duplicate_connection}
        else
          {:error, changeset}
        end
    end
  end

  defp connected_player_for(
         %BingoConnection{player_id: player_id, connected_player: connected},
         player_id
       ),
       do: connected

  defp connected_player_for(%BingoConnection{player: player}, _player_id), do: player

  defp forum_profile(%BingoPlayer{} = player) do
    %{
      id: player.id,
      name: player.name,
      title: player.title,
      company: player.company,
      intro: player.intro,
      joined_at: player.inserted_at
    }
  end

  defp base_profile(%BingoPlayer{} = player) do
    %{
      id: player.id,
      name: player.name,
      code: player.code
    }
  end

  defp present?(nil), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: true

  defp count_connections(event_id) do
    from(c in BingoConnection, where: c.event_id == ^event_id)
    |> Repo.aggregate(:count, :id)
  end

  defp prompt_performance(prompts) do
    Enum.map(prompts, fn prompt ->
      %{
        prompt_id: prompt.id,
        prompt: prompt.prompt,
        connection_count: count_prompt_connections(prompt.id)
      }
    end)
  end

  defp count_prompt_connections(prompt_id) do
    from(c in BingoConnection, where: c.bingo_prompt_id == ^prompt_id)
    |> Repo.aggregate(:count, :id)
  end

  defp percentage(_count, 0), do: 0
  defp percentage(count, total), do: round(count / total * 100)

  defp format_naive_datetime(nil), do: ""

  defp format_naive_datetime(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp target_index(index, :up), do: index - 1
  defp target_index(index, :down), do: index + 1

  defp put_create_position(attrs) do
    event_id = attrs |> attr(:event_id) |> parse_id()
    put_attr(attrs, :position, next_position(event_id))
  end

  defp maybe_put_moved_position(attrs, old_event_id) do
    new_event_id = attrs |> attr(:event_id) |> parse_id()

    if new_event_id && new_event_id != old_event_id do
      put_attr(attrs, :position, next_position(new_event_id))
    else
      attrs
    end
  end

  defp pair_key(player_id, connected_player_id) do
    [player_id, connected_player_id]
    |> Enum.sort()
    |> Enum.join(":")
  end

  defp generate_code do
    @code_length
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(case: :upper, padding: false)
    |> binary_part(0, @code_length)
  end

  defp normalize_code(nil), do: nil

  defp normalize_code(code) do
    code
    |> to_string()
    |> String.trim()
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9]/, "")
  end

  defp unique_code_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {:code, {_message, opts}} -> opts[:constraint_name] == "bingo_players_event_code_unique"
      _ -> false
    end)
  end

  defp duplicate_connection_error?(changeset) do
    Enum.any?(changeset.errors, fn
      {field, {_message, opts}} when field in [:player_id, :pair_key] ->
        opts[:constraint_name] in [
          "bingo_connections_prompt_player_unique",
          "bingo_connections_prompt_pair_unique"
        ]

      _ ->
        false
    end)
  end

  defp attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key) || Map.get(attrs, to_string(key))

  defp put_attr(attrs, key, value) when is_map(attrs) do
    if has_string_keys?(attrs) do
      Map.put(attrs, to_string(key), value)
    else
      Map.put(attrs, key, value)
    end
  end

  defp delete_attr(attrs, key) when is_map(attrs) do
    attrs
    |> Map.delete(key)
    |> Map.delete(to_string(key))
  end

  defp has_string_keys?(attrs) do
    attrs != %{} && Enum.all?(Map.keys(attrs), &is_binary/1)
  end

  defp parse_id(nil), do: nil
  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
