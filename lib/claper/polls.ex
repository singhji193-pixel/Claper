defmodule Claper.Polls do
  @moduledoc """
  The Polls context.
  """

  import Ecto.Query, warn: false
  alias Claper.Repo

  alias Claper.Polls.Poll
  alias Claper.Polls.PollOpt
  alias Claper.Polls.PollVote

  @doc """
  Returns the list of polls for a given presentation file.

  ## Examples

      iex> list_polls(123)
      [%Poll{}, ...]

  """
  def list_polls(presentation_file_id) do
    from(p in Poll,
      where: p.presentation_file_id == ^presentation_file_id,
      order_by: [asc: p.id, asc: p.position]
    )
    |> Repo.all()
    |> Repo.preload([:poll_opts])
  end

  @doc """
  Returns the list of polls for a given presentation file and a given position.

  ## Examples

      iex> list_polls_at_position(123, 0)
      [%Poll{}, ...]

  """
  def list_polls_at_position(presentation_file_id, position) do
    from(p in Poll,
      where: p.presentation_file_id == ^presentation_file_id and p.position == ^position,
      order_by: [asc: p.id]
    )
    |> Repo.all()
    |> Repo.preload([:poll_opts])
  end

  @doc """
  Gets a single poll and set percentages for each poll options.

  Raises `Ecto.NoResultsError` if the Poll does not exist.

  ## Examples

      iex> get_poll!(123)
      %Poll{}

      iex> get_poll!(456)
      ** (Ecto.NoResultsError)

  """
  def get_poll!(id),
    do:
      Repo.get!(Poll, id)
      |> Repo.preload(
        poll_opts:
          from(
            o in PollOpt,
            order_by: [asc: o.id]
          )
      )
      |> set_percentages()

  @doc """
  Gets a single poll scoped to the given event.

  Returns `nil` if the poll does not exist or does not belong to the event.
  """
  def get_poll_for_event(id, event_id) do
    from(p in Poll,
      join: pf in assoc(p, :presentation_file),
      where: p.id == ^id and pf.event_id == ^event_id
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      poll ->
        poll
        |> Repo.preload(
          poll_opts:
            from(
              o in PollOpt,
              order_by: [asc: o.id]
            )
        )
        |> set_percentages()
    end
  end

  @doc """
  Gets a single poll for a given position.

  ## Examples

      iex> get_poll!(123, 0)
      %Poll{}

  """
  def get_poll_current_position(presentation_file_id, position) do
    from(p in Poll,
      where:
        p.position == ^position and p.presentation_file_id == ^presentation_file_id and
          p.enabled == true
    )
    |> Repo.one()
    |> Repo.preload(
      poll_opts:
        from(
          o in PollOpt,
          order_by: [asc: o.id]
        )
    )
    |> set_percentages()
  end

  @doc """
  Calculate percentage of all poll options for a given poll.

  ## Examples

      iex> set_percentages(poll)
      %Poll{}

  """
  def set_percentages(%Poll{poll_opts: poll_opts} = poll) when is_list(poll_opts) do
    total = Enum.map(poll.poll_opts, fn e -> e.vote_count end) |> Enum.sum()

    %{
      poll
      | poll_opts:
          poll.poll_opts
          |> Enum.map(fn o -> %{o | percentage: calculate_percentage(o, total)} end)
    }
  end

  def set_percentages(poll), do: poll

  defp calculate_percentage(opt, total) do
    if total > 0,
      do: Float.round(opt.vote_count / total * 100) |> :erlang.float_to_binary(decimals: 0),
      else: 0
  end

  @doc """
  Creates a poll.

  ## Examples

      iex> create_poll(%{field: value})
      {:ok, %Poll{}}

      iex> create_poll(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_poll(attrs \\ %{}) do
    %Poll{}
    |> Poll.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, poll} ->
        poll = Repo.preload(poll, presentation_file: :event)
        broadcast({:ok, poll, poll.presentation_file.event.uuid}, :poll_created)

      {:error, changeset} ->
        {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Updates a poll.

  ## Examples

      iex> update_poll("123e4567-e89b-12d3-a456-426614174000", poll, %{field: new_value})
      {:ok, %Poll{}}

      iex> update_poll("123e4567-e89b-12d3-a456-426614174000", poll, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_poll(event_uuid, %Poll{} = poll, attrs) do
    poll
    |> Poll.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, poll} ->
        broadcast({:ok, poll, event_uuid}, :poll_updated)

      {:error, changeset} ->
        {:error, %{changeset | action: :update}}
    end
  end

  @doc """
  Deletes a poll.

  ## Examples

      iex> delete_poll("123e4567-e89b-12d3-a456-426614174000", poll)
      {:ok, %Poll{}}

      iex> delete_poll("123e4567-e89b-12d3-a456-426614174000", poll)
      {:error, %Ecto.Changeset{}}

  """
  def delete_poll(event_uuid, %Poll{} = poll) do
    {:ok, poll} = Repo.delete(poll)
    broadcast({:ok, poll, event_uuid}, :poll_deleted)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking poll changes.

  ## Examples

      iex> change_poll(poll)
      %Ecto.Changeset{data: %Poll{}}

  """
  def change_poll(%Poll{} = poll, attrs \\ %{}) do
    Poll.changeset(poll, attrs)
  end

  @doc """
  Add an empty poll opt to a poll changeset.
  """
  def add_poll_opt(changeset) do
    changeset
    |> Ecto.Changeset.put_assoc(
      :poll_opts,
      Ecto.Changeset.get_field(changeset, :poll_opts) ++ [%PollOpt{}]
    )
  end

  @doc """
  Remove a poll opt from a poll changeset.
  """
  def remove_poll_opt(changeset, poll_opt) do
    changeset
    |> Ecto.Changeset.put_assoc(
      :poll_opts,
      Ecto.Changeset.get_field(changeset, :poll_opts) -- [poll_opt]
    )
  end

  def vote(user_id, event_uuid, poll_opts, poll_id)
      when is_number(user_id) and is_list(poll_opts) do
    submit_vote({:user, user_id}, event_uuid, poll_opts, poll_id)
  end

  def vote(attendee_identifier, event_uuid, poll_opts, poll_id)
      when is_binary(attendee_identifier) and byte_size(attendee_identifier) > 0 and
             is_list(poll_opts) do
    submit_vote({:attendee, attendee_identifier}, event_uuid, poll_opts, poll_id)
  end

  def vote(_identity, _event_uuid, _poll_opts, _poll_id), do: {:error, :invalid_identity}

  def disable_all(presentation_file_id, position) do
    from(p in Poll,
      where: p.presentation_file_id == ^presentation_file_id and p.position == ^position
    )
    |> Repo.update_all(set: [enabled: false])
  end

  def set_enabled(id) do
    get_poll!(id)
    |> Ecto.Changeset.change(enabled: true)
    |> Repo.update()
  end

  def set_disabled(id) do
    get_poll!(id)
    |> Ecto.Changeset.change(enabled: false)
    |> Repo.update()
  end

  defp broadcast({:ok, poll, event_uuid}, event) do
    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{event_uuid}",
      {event, poll}
    )

    {:ok, poll}
  end

  @doc """
  Gets a all poll_vote.


  ## Examples

      iex> get_poll_vote!(321, 123)
      [%PollVote{}]

  """
  def get_poll_vote(user_id, poll_id) when is_number(user_id) do
    from(p in PollVote,
      where: p.poll_id == ^poll_id and p.user_id == ^user_id,
      order_by: [asc: p.id]
    )
    |> Repo.all()
  end

  def get_poll_vote(attendee_identifier, poll_id) do
    from(p in PollVote,
      where: p.poll_id == ^poll_id and p.attendee_identifier == ^attendee_identifier,
      order_by: [asc: p.id]
    )
    |> Repo.all()
  end

  @doc """
  Creates a poll_vote.

  ## Examples

      iex> create_poll_vote(%{field: value})
      {:ok, %PollVote{}}

      iex> create_poll_vote(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_poll_vote(attrs \\ %{}) do
    %PollVote{}
    |> PollVote.changeset(attrs)
    |> Repo.insert()
  end

  defp submit_vote(identity, event_ref, submitted_opts, poll_id) do
    option_ids = submitted_opts |> Enum.map(&option_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    Repo.transaction(fn ->
      poll =
        Poll
        |> where([poll], poll.id == ^poll_id)
        |> lock("FOR UPDATE")
        |> preload([:poll_opts, presentation_file: :event])
        |> Repo.one()

      with %Poll{} <- poll,
           :ok <- validate_event_ref(poll, event_ref),
           :ok <- validate_poll_selection(poll, option_ids) do
        unless single_choice_already_submitted?(poll, identity) do
          Enum.each(option_ids, &insert_vote(poll.id, &1, identity))
        end

        get_poll!(poll.id)
      else
        nil -> Repo.rollback(:interaction_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, poll} -> broadcast({:ok, poll, event_uuid(poll_id)}, :poll_updated)
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_vote(poll_id, poll_opt_id, identity) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    attrs =
      identity
      |> identity_attrs()
      |> Map.merge(%{
        poll_id: poll_id,
        poll_opt_id: poll_opt_id,
        inserted_at: now,
        updated_at: now
      })

    case Repo.insert_all(PollVote, [attrs], on_conflict: :nothing) do
      {1, _rows} ->
        from(option in PollOpt, where: option.id == ^poll_opt_id)
        |> Repo.update_all(inc: [vote_count: 1])

      {0, _rows} ->
        :ok
    end
  end

  defp validate_poll_selection(%Poll{} = poll, option_ids) do
    allowed_ids = MapSet.new(poll.poll_opts, & &1.id)

    cond do
      option_ids == [] -> {:error, :invalid_selection}
      not poll.multiple and length(option_ids) != 1 -> {:error, :invalid_selection}
      Enum.any?(option_ids, &(not MapSet.member?(allowed_ids, &1))) -> {:error, :invalid_option}
      true -> :ok
    end
  end

  defp single_choice_already_submitted?(%Poll{multiple: true}, _identity), do: false

  defp single_choice_already_submitted?(%Poll{id: poll_id}, identity) do
    query = from(vote in PollVote, where: vote.poll_id == ^poll_id)
    Repo.exists?(identity_query(query, identity))
  end

  defp validate_event_ref(%Poll{presentation_file: %{event: event}}, event_ref) do
    if event_ref in [event.id, event.uuid], do: :ok, else: {:error, :event_mismatch}
  end

  defp identity_attrs({:user, user_id}), do: %{user_id: user_id}

  defp identity_attrs({:attendee, attendee_identifier}),
    do: %{attendee_identifier: attendee_identifier}

  defp identity_query(query, {:user, user_id}), do: where(query, [vote], vote.user_id == ^user_id)

  defp identity_query(query, {:attendee, attendee_identifier}),
    do: where(query, [vote], vote.attendee_identifier == ^attendee_identifier)

  defp option_id(%{id: id}) when is_integer(id), do: id
  defp option_id(id) when is_integer(id), do: id

  defp option_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp option_id(_option), do: nil

  defp event_uuid(poll_id) do
    Poll
    |> Repo.get!(poll_id)
    |> Repo.preload(presentation_file: :event)
    |> then(& &1.presentation_file.event.uuid)
  end
end
