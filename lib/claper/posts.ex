defmodule Claper.Posts do
  @moduledoc """
  The Posts context.
  """

  import Ecto.Query, warn: false
  alias Claper.Repo

  alias Claper.Posts.Post

  @doc """
  Get event posts

  """
  def list_posts(event_id, preload \\ []) do
    from(p in Post,
      join: e in Claper.Events.Event,
      on: p.event_id == e.id,
      select: p,
      where: e.uuid == ^event_id,
      order_by: [asc: p.id]
    )
    |> Repo.all()
    |> Repo.preload(preload)
  end

  @doc """
  Get event posts which are questions

  """
  def list_questions(event_id, preload \\ [], sort \\ :date) do
    query =
      from(p in Post,
        join: e in assoc(p, :event),
        where: e.uuid == ^event_id and p.kind == "question"
      )

    query =
      case sort do
        :likes -> from(p in query, order_by: [desc: p.like_count])
        _ -> from(p in query, order_by: [asc: p.id])
      end

    query
    |> Repo.all()
    |> Repo.preload(preload)
  end

  @doc """
  Get only the pinned event posts.
  """
  def list_pinned_posts(event_id, preload \\ []) do
    from(p in Post,
      join: e in Claper.Events.Event,
      on: p.event_id == e.id,
      select: p,
      # Only pinned posts
      where: e.uuid == ^event_id and p.pinned == true,
      order_by: [asc: p.id]
    )
    |> Repo.all()
    |> Repo.preload(preload)
  end

  @doc """
  Get only the unpinned event posts.
  """
  def list_unpinned_posts(event_id, preload \\ []) do
    from(p in Post,
      join: e in Claper.Events.Event,
      on: p.event_id == e.id,
      select: p,
      # Only unpinned posts
      where: e.uuid == ^event_id and p.pinned == false,
      order_by: [asc: p.id]
    )
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def reacted_posts(event_id, user_id, icon) when is_number(user_id) do
    from(reaction in Claper.Posts.Reaction,
      join: post in Claper.Posts.Post,
      on: reaction.post_id == post.id,
      where:
        reaction.icon == ^icon and reaction.user_id == ^user_id and
          post.event_id == ^event_id,
      distinct: true,
      select: reaction.post_id
    )
    |> Repo.all()
  end

  def reacted_posts(event_id, attendee_identifier, icon) do
    from(reaction in Claper.Posts.Reaction,
      join: post in Claper.Posts.Post,
      on: reaction.post_id == post.id,
      where:
        reaction.icon == ^icon and
          reaction.attendee_identifier == ^attendee_identifier and post.event_id == ^event_id,
      distinct: true,
      select: reaction.post_id
    )
    |> Repo.all()
  end

  @doc """
  Gets a single post.

  Raises `Ecto.NoResultsError` if the Post does not exist.

  ## Examples

      iex> get_post!("123e4567-e89b-12d3-a456-426614174000")
      %Post{}

      iex> get_post!("123e4567-e89b-12d3-a456-426614174123")
      ** (Ecto.NoResultsError)

  """
  def get_post!(id, preload \\ []), do: Repo.get_by!(Post, uuid: id) |> Repo.preload(preload)

  @doc """
  Gets a single post scoped to the given event.

  Returns `nil` if the post does not exist or does not belong to the event.
  """
  def get_post_for_event(uuid, event_id, preload \\ []) do
    from(p in Post,
      where: p.uuid == ^uuid and p.event_id == ^event_id
    )
    |> Repo.one()
    |> case do
      nil -> nil
      post -> Repo.preload(post, preload)
    end
  end

  @doc """
  Creates a post.

  ## Examples

      iex> create_post(event, %{field: value})
      {:ok, %Post{}}

      iex> create_post(event, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_post(event, attrs) do
    attrs = put_default_kind(attrs)

    %Post{}
    |> Map.put(:event, event)
    |> Post.changeset(attrs)
    |> Repo.insert(returning: [:uuid])
    |> broadcast(:post_created)
  end

  def list_posts_by_kind(event_uuid, kind, preload \\ []) when kind in ["question", "message"] do
    from(post in Post,
      join: event in assoc(post, :event),
      where: event.uuid == ^event_uuid and post.kind == ^kind,
      order_by: [desc: post.pinned, asc: post.id]
    )
    |> Repo.all()
    |> Repo.preload(preload)
  end

  @doc """
  Updates a post.

  ## Examples

      iex> update_post(post, %{field: new_value})
      {:ok, %Post{}}

      iex> update_post(post, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_post(%Post{} = post, attrs) do
    changeset = Post.changeset(post, attrs)

    result = changeset |> Repo.update()

    result |> broadcast(:post_updated)
  end

  @doc """
  Pins or unpins a post based on its current state.

  ## Examples

      iex> toggle_pin_post(post)
      {:ok, %Post{}}

      iex> toggle_pin_post(invalid_post)
      {:error, %Ecto.Changeset{}}

  """
  def toggle_pin_post(%Post{} = post) do
    # Toggling the pinned state
    new_pinned_state = not post.pinned
    changeset = Post.changeset(post, %{pinned: new_pinned_state})

    result = changeset |> Repo.update()

    # Broadcast the appropriate message based on the new state
    broadcast_message =
      if new_pinned_state do
        :post_pinned
      else
        :post_unpinned
      end

    result |> broadcast(broadcast_message)
  end

  @doc """
  Deletes a post.

  ## Examples

      iex> delete_post(post)
      {:ok, %Post{}}

      iex> delete_post(post)
      {:error, %Ecto.Changeset{}}

  """
  def delete_post(%Post{} = post) do
    post
    |> Repo.delete()
    |> broadcast(:post_deleted)
  end

  def delete_all_posts(:attendee_identifier, attendee_identifier, event) do
    posts =
      from(post in Claper.Posts.Post,
        where: post.attendee_identifier == ^attendee_identifier and post.event_id == ^event.id
      )
      |> Repo.all()

    for post <- posts do
      delete_post(%{post | event: event})
    end
  end

  def delete_all_posts(:user_id, user_id, event) do
    posts =
      from(post in Claper.Posts.Post,
        where: post.user_id == ^user_id and post.event_id == ^event.id
      )
      |> Repo.all()

    for post <- posts do
      delete_post(%{post | event: event})
    end
  end

  alias Claper.Posts.{Reaction, Post}

  @doc """
  Gets a single reaction.

  Raises `Ecto.NoResultsError` if the Reaction does not exist.

  ## Examples

      iex> get_reaction!(123)
      %Reaction{}

      iex> get_reaction!(456)
      ** (Ecto.NoResultsError)

  """
  def get_reaction!(id), do: Repo.get!(Reaction, id)

  @doc """
  Creates a reaction.

  ## Examples

      iex> create_reaction(%{field: value})
      {:ok, %Reaction{}}

      iex> create_reaction(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_reaction(%{post: nil} = attrs), do: create_reaction(%{attrs | post: %Post{}})

  def create_reaction(%{post: post} = attrs) do
    case %Reaction{}
         |> Map.put(:post_id, post.id)
         |> Reaction.changeset(attrs)
         |> Repo.insert() do
      {:ok, reaction} ->
        broadcast({:ok, post}, :reaction_added)
        {:ok, reaction}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes a reaction.

  ## Examples

      iex> delete_reaction(reaction)
      {:ok, %Reaction{}}

      iex> delete_reaction(reaction)
      {:error, %Ecto.Changeset{}}

  """
  def delete_reaction(%{user_id: user_id, post: post, icon: icon} = _params)
      when is_integer(user_id) do
    with reaction <- Repo.get_by!(Reaction, post_id: post.id, user_id: user_id, icon: icon) do
      Repo.delete(reaction)
      broadcast({:ok, post}, :reaction_removed)
    end
  end

  def delete_reaction(
        %{attendee_identifier: attendee_identifier, post: post, icon: icon} = _params
      ) do
    with reaction <-
           Repo.get_by!(Reaction,
             post_id: post.id,
             attendee_identifier: attendee_identifier,
             icon: icon
           ) do
      Repo.delete(reaction)
      broadcast({:ok, post}, :reaction_removed)
    end
  end

  def toggle_attendee_reaction(event_id, attendee_identifier, post_uuid, icon)
      when is_binary(attendee_identifier) and icon in ["👍", "❤️", "😂"] do
    Repo.transaction(fn ->
      post =
        Post
        |> where([post], post.uuid == ^post_uuid and post.event_id == ^event_id)
        |> lock("FOR UPDATE")
        |> preload(:event)
        |> Repo.one()

      if is_nil(post), do: Repo.rollback(:post_not_found)

      reaction =
        Repo.get_by(Reaction,
          post_id: post.id,
          attendee_identifier: attendee_identifier,
          icon: icon
        )

      {status, delta} =
        case reaction do
          %Reaction{} = reaction ->
            Repo.delete!(reaction)
            {:removed, -1}

          nil ->
            %Reaction{}
            |> Reaction.changeset(%{
              post_id: post.id,
              attendee_identifier: attendee_identifier,
              icon: icon
            })
            |> Repo.insert!()

            {:added, 1}
        end

      field = reaction_count_field(icon)

      from(entry in Post, where: entry.id == ^post.id)
      |> Repo.update_all(inc: [{field, delta}])

      updated_post = post.uuid |> get_post!([:event, :reactions])
      {status, updated_post}
    end)
    |> case do
      {:ok, {status, post}} ->
        event = if status == :added, do: :reaction_added, else: :reaction_removed
        {:ok, _post} = broadcast({:ok, post}, event)
        {:ok, status, post}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def toggle_attendee_reaction(_event_id, _attendee_identifier, _post_uuid, _icon),
    do: {:error, :invalid_reaction}

  defp broadcast({:error, _reason} = error, _event), do: error

  defp broadcast({:ok, post}, event) do
    Phoenix.PubSub.broadcast(Claper.PubSub, "event:#{post.event.uuid}", {event, post})
    {:ok, post}
  end

  defp reaction_count_field("👍"), do: :like_count
  defp reaction_count_field("❤️"), do: :love_count
  defp reaction_count_field("😂"), do: :lol_count

  defp put_default_kind(attrs) when is_map(attrs) do
    if Map.has_key?(attrs, :kind) or Map.has_key?(attrs, "kind") do
      attrs
    else
      body = Map.get(attrs, :body) || Map.get(attrs, "body") || ""
      kind = if String.contains?(body, "?"), do: "question", else: "message"

      if Enum.all?(Map.keys(attrs), &is_atom/1),
        do: Map.put(attrs, :kind, kind),
        else: Map.put(attrs, "kind", kind)
    end
  end
end
