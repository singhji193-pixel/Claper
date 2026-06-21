defmodule Claper.Agendas do
  @moduledoc """
  The Agendas context.
  """

  import Ecto.Query, warn: false

  alias Claper.Agendas.{AgendaItem, AgendaResource}
  alias Claper.Repo

  @doc """
  Returns ordered agenda items for an event.
  """
  def list_agenda_items(nil), do: []

  def list_agenda_items(event_id) do
    from(a in AgendaItem,
      where: a.event_id == ^event_id,
      order_by: [asc: a.position, asc: a.starts_at, asc: a.id]
    )
    |> Repo.all()
  end

  def list_agenda_items_for_app(event_id, opts \\ []) do
    event_id
    |> list_agenda_items()
    |> filter_by_day(Keyword.get(opts, :day))
    |> filter_by_track(Keyword.get(opts, :track))
  end

  @doc """
  Gets a single agenda item.
  """
  def get_agenda_item!(id, preload \\ []),
    do: Repo.get!(AgendaItem, id) |> Repo.preload(preload)

  @doc """
  Gets a single agenda item scoped to an event.
  """
  def get_agenda_item_for_event!(event_id, id) do
    from(a in AgendaItem, where: a.event_id == ^event_id and a.id == ^id)
    |> Repo.one!()
  end

  def get_agenda_item_for_event(event_id, id) do
    with id when not is_nil(id) <- parse_id(id) do
      from(a in AgendaItem, where: a.event_id == ^event_id and a.id == ^id)
      |> Repo.one()
    end
  end

  def agenda_days(event_id) do
    event_id
    |> list_agenda_items()
    |> Enum.map(&NaiveDateTime.to_date(&1.starts_at))
    |> Enum.uniq()
  end

  def agenda_tracks(event_id) do
    event_id
    |> list_agenda_items()
    |> Enum.map(&normalize_blank(&1.track_name))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  Returns an agenda item changeset.
  """
  def change_agenda_item(%AgendaItem{} = agenda_item, attrs \\ %{}) do
    AgendaItem.changeset(agenda_item, attrs)
  end

  @doc """
  Creates an agenda item and appends it to the selected event.
  """
  def create_agenda_item(attrs \\ %{}) do
    Repo.transaction(fn ->
      attrs = put_create_position(attrs)

      %AgendaItem{}
      |> AgendaItem.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, agenda_item} ->
          normalize_positions(agenda_item.event_id)
          agenda_item

        {:error, changeset} ->
          Repo.rollback(%{changeset | action: :insert})
      end
    end)
  end

  @doc """
  Updates an agenda item.
  """
  def update_agenda_item(%AgendaItem{} = agenda_item, attrs) do
    Repo.transaction(fn ->
      old_event_id = agenda_item.event_id
      attrs = maybe_put_moved_position(attrs, old_event_id)

      agenda_item
      |> AgendaItem.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, agenda_item} ->
          normalize_positions(old_event_id)
          normalize_positions(agenda_item.event_id)
          agenda_item

        {:error, changeset} ->
          Repo.rollback(%{changeset | action: :update})
      end
    end)
  end

  @doc """
  Deletes an agenda item and compacts positions for its event.
  """
  def delete_agenda_item(%AgendaItem{} = agenda_item) do
    Repo.transaction(fn ->
      event_id = agenda_item.event_id

      case Repo.delete(agenda_item) do
        {:ok, agenda_item} ->
          normalize_positions(event_id)
          agenda_item

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Moves an agenda item one position up or down within an event.
  """
  def move_agenda_item(event_id, agenda_item_id, direction) when direction in [:up, :down] do
    Repo.transaction(fn ->
      normalize_positions(event_id)
      items = list_agenda_items(event_id)
      current_index = Enum.find_index(items, &("#{&1.id}" == "#{agenda_item_id}"))

      if is_nil(current_index) do
        Repo.rollback(:not_found)
      else
        target_index = target_index(current_index, direction)

        cond do
          target_index < 0 or target_index >= length(items) ->
            items

          true ->
            current = Enum.at(items, current_index)
            target = Enum.at(items, target_index)

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

  def move_agenda_item(_event_id, _agenda_item_id, _direction), do: {:error, :invalid_direction}

  def next_position(nil), do: 0

  def next_position(event_id) do
    from(a in AgendaItem,
      where: a.event_id == ^event_id,
      select: max(a.position)
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
    |> list_agenda_items()
    |> Enum.with_index()
    |> Enum.each(fn {agenda_item, position} ->
      if agenda_item.position != position do
        agenda_item
        |> Ecto.Changeset.change(position: position)
        |> Repo.update!()
      end
    end)

    list_agenda_items(event_id)
  end

  def list_resources(agenda_item_id, opts \\ []) do
    query =
      from(resource in AgendaResource,
        where: resource.agenda_item_id == ^agenda_item_id,
        order_by: [asc: resource.position, asc: resource.id]
      )

    query =
      if Keyword.get(opts, :published_only, false),
        do: where(query, [resource], resource.published == true),
        else: query

    Repo.all(query)
  end

  def get_resource_for_event(event_id, resource_id) do
    with id when not is_nil(id) <- parse_id(resource_id) do
      Repo.get_by(AgendaResource, id: id, event_id: event_id)
    end
  end

  def change_resource(%AgendaResource{} = resource, attrs \\ %{}) do
    AgendaResource.changeset(resource, attrs)
  end

  def create_resource(attrs) do
    with {:ok, event_id, agenda_item_id} <- resource_scope(attrs) do
      attrs =
        attrs
        |> put_attr(:event_id, event_id)
        |> put_attr(:agenda_item_id, agenda_item_id)
        |> put_attr(:position, next_resource_position(agenda_item_id))

      %AgendaResource{}
      |> AgendaResource.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_resource(%AgendaResource{} = resource, attrs) do
    attrs =
      attrs
      |> put_attr(:event_id, resource.event_id)
      |> put_attr(:agenda_item_id, resource.agenda_item_id)

    resource
    |> AgendaResource.changeset(attrs)
    |> Repo.update()
  end

  def delete_resource(%AgendaResource{} = resource) do
    case Repo.delete(resource) do
      {:ok, deleted} ->
        normalize_resource_positions(resource.agenda_item_id)
        {:ok, deleted}

      error ->
        error
    end
  end

  def move_resource(event_id, resource_id, direction) when direction in [:up, :down] do
    Repo.transaction(fn ->
      resource = get_resource_for_event(event_id, resource_id)

      if is_nil(resource) do
        Repo.rollback(:not_found)
      else
        resources = normalize_resource_positions(resource.agenda_item_id)
        index = Enum.find_index(resources, &(&1.id == resource.id))
        target_index = target_index(index, direction)

        if target_index >= 0 and target_index < length(resources) do
          target = Enum.at(resources, target_index)

          resource |> Ecto.Changeset.change(position: target.position) |> Repo.update!()
          target |> Ecto.Changeset.change(position: resource.position) |> Repo.update!()
        end

        normalize_resource_positions(resource.agenda_item_id)
      end
    end)
  end

  def move_resource(_event_id, _resource_id, _direction), do: {:error, :invalid_direction}

  defp next_resource_position(agenda_item_id) do
    from(resource in AgendaResource,
      where: resource.agenda_item_id == ^agenda_item_id,
      select: max(resource.position)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      position -> position + 1
    end
  end

  defp normalize_resource_positions(agenda_item_id) do
    agenda_item_id
    |> list_resources()
    |> Enum.with_index()
    |> Enum.each(fn {resource, position} ->
      if resource.position != position do
        resource |> Ecto.Changeset.change(position: position) |> Repo.update!()
      end
    end)

    list_resources(agenda_item_id)
  end

  defp resource_scope(attrs) do
    event_id = attrs |> attr(:event_id) |> parse_id()
    agenda_item_id = attrs |> attr(:agenda_item_id) |> parse_id()

    if event_id && agenda_item_id do
      case get_agenda_item_for_event(event_id, agenda_item_id) do
        %AgendaItem{} -> {:ok, event_id, agenda_item_id}
        nil -> {:error, :agenda_item_not_found}
      end
    else
      {:error, :agenda_item_not_found}
    end
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

  defp attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key) || Map.get(attrs, to_string(key))

  defp put_attr(attrs, key, value) when is_map(attrs) do
    if has_string_keys?(attrs) do
      Map.put(attrs, to_string(key), value)
    else
      Map.put(attrs, key, value)
    end
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

  defp filter_by_day(items, nil), do: items
  defp filter_by_day(items, ""), do: items

  defp filter_by_day(items, day) when is_binary(day) do
    case Date.from_iso8601(day) do
      {:ok, date} -> filter_by_day(items, date)
      {:error, _reason} -> items
    end
  end

  defp filter_by_day(items, %Date{} = day) do
    Enum.filter(items, &(NaiveDateTime.to_date(&1.starts_at) == day))
  end

  defp filter_by_track(items, nil), do: items
  defp filter_by_track(items, ""), do: items
  defp filter_by_track(items, "all"), do: items

  defp filter_by_track(items, track) when is_binary(track) do
    Enum.filter(items, &(normalize_blank(&1.track_name) == track))
  end

  defp normalize_blank(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_blank(_value), do: nil
end
