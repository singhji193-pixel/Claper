defmodule Claper.Forms do
  @moduledoc """
  The Forms context.
  """

  import Ecto.Query, warn: false
  alias Claper.Repo

  alias Claper.Forms.Form
  alias Claper.Forms.FormSubmit
  alias Claper.Forms.Field

  @doc """
  Returns the list of forms for a given presentation file.

  ## Examples

      iex> list_forms(123)
      [%Form{}, ...]

  """
  def list_forms(presentation_file_id) do
    from(f in Form,
      where: f.presentation_file_id == ^presentation_file_id,
      order_by: [asc: f.id, asc: f.position]
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of forms for a given presentation file and a given position.

  ## Examples

      iex> list_forms_at_position(123, 0)
      [%Form{}, ...]

  """
  def list_forms_at_position(presentation_file_id, position) do
    from(f in Form,
      where: f.presentation_file_id == ^presentation_file_id and f.position == ^position,
      order_by: [asc: f.id]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single form.

  Raises `Ecto.NoResultsError` if the Form does not exist.

  ## Examples

      iex> get_form!(123)
      %Poll{}

      iex> get_form!(456)
      ** (Ecto.NoResultsError)

  """
  def get_form!(id, preload \\ []),
    do: Repo.get!(Form, id) |> Repo.preload(preload)

  @doc """
  Gets a single form scoped to the given event.

  Returns `nil` if the form does not exist or does not belong to the event.
  """
  def get_form_for_event(id, event_id, preload \\ []) do
    from(f in Form,
      join: pf in assoc(f, :presentation_file),
      where: f.id == ^id and pf.event_id == ^event_id
    )
    |> Repo.one()
    |> case do
      nil -> nil
      form -> Repo.preload(form, preload)
    end
  end

  @doc """
  Gets a single form for a given position.

  ## Examples

      iex> get_form!(123, 0)
      %Form{}

  """
  def get_form_current_position(presentation_file_id, position) do
    from(f in Form,
      where:
        f.position == ^position and f.presentation_file_id == ^presentation_file_id and
          f.enabled == true
    )
    |> Repo.one()
  end

  @doc """
  Creates a form.

  ## Examples

      iex> create_form(%{field: value})
      {:ok, %Form{}}

      iex> create_form(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_form(attrs \\ %{}) do
    %Form{}
    |> Form.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, form} ->
        form = Repo.preload(form, presentation_file: :event)
        broadcast({:ok, form, form.presentation_file.event.uuid}, :form_created)

      {:error, changeset} ->
        {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Updates a form.

  ## Examples

      iex> update_form("123e4567-e89b-12d3-a456-426614174000", form, %{field: new_value})
      {:ok, %Form{}}

      iex> update_form("123e4567-e89b-12d3-a456-426614174000", form, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_form(event_uuid, %Form{} = form, attrs) do
    form
    |> Form.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, form} ->
        broadcast({:ok, form, event_uuid}, :form_updated)

      {:error, changeset} ->
        {:error, %{changeset | action: :update}}
    end
  end

  @doc """
  Deletes a form.

  ## Examples

      iex> delete_form("123e4567-e89b-12d3-a456-426614174000", form)
      {:ok, %Form{}}

      iex> delete_form("123e4567-e89b-12d3-a456-426614174000", form)
      {:error, %Ecto.Changeset{}}

  """
  def delete_form(event_uuid, %Form{} = form) do
    {:ok, form} = Repo.delete(form)
    broadcast({:ok, form, event_uuid}, :form_deleted)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking form changes.

  ## Examples

      iex> change_form(form)
      %Ecto.Changeset{data: %Form{}}

  """
  def change_form(%Form{} = form, attrs \\ %{}) do
    Form.changeset(form, attrs)
  end

  @doc """
  Add an empty form field to a form changeset.
  """
  def add_form_field(changeset) do
    changeset
    |> Ecto.Changeset.put_embed(
      :fields,
      Ecto.Changeset.get_field(changeset, :fields) ++ [%Field{}]
    )
  end

  @doc """
  Remove a form field from a form changeset.
  """
  def remove_form_field(changeset, field) do
    changeset
    |> Ecto.Changeset.put_embed(
      :fields,
      Ecto.Changeset.get_field(changeset, :fields) -- [field]
    )
  end

  def disable_all(presentation_file_id, position) do
    from(f in Form,
      where: f.presentation_file_id == ^presentation_file_id and f.position == ^position
    )
    |> Repo.update_all(set: [enabled: false])
  end

  def set_enabled(id) do
    get_form!(id)
    |> Ecto.Changeset.change(enabled: true)
    |> Repo.update()
  end

  def set_disabled(id) do
    get_form!(id)
    |> Ecto.Changeset.change(enabled: false)
    |> Repo.update()
  end

  defp broadcast({:ok, form, event_uuid}, event) do
    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{event_uuid}",
      {event, form}
    )

    {:ok, form}
  end

  @doc """
  Creates a form submit.

  ## Examples

      iex> create_form_submit(%{field: value})
      {:ok, %FormSubmit{}}

      iex> create_form_submit(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_form_submit(attrs \\ %{}) do
    %FormSubmit{}
    |> FormSubmit.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the list of form submissions for a given presentation file.

  ## Examples

      iex> list_form_submits(123)
      [%FormSubmit{}, ...]

  """
  def list_form_submits(presentation_file_id, preload \\ []) do
    from(fs in FormSubmit,
      join: f in Form,
      on: f.id == fs.form_id,
      where: f.presentation_file_id == ^presentation_file_id
    )
    |> Repo.all()
    |> Repo.preload(preload)
  end

  @doc """
  Gets a single FormSubmit.

  ## Examples

      iex> get_form_submit!(321, 123)
      %FormSubmit{}

  """
  def get_form_submit(user_id, form_id) when is_number(user_id),
    do: Repo.get_by(FormSubmit, form_id: form_id, user_id: user_id)

  def get_form_submit(attendee_identifier, form_id),
    do: Repo.get_by(FormSubmit, form_id: form_id, attendee_identifier: attendee_identifier)

  @doc """
  Gets a single FormSubmit by its ID.

  Raises `Ecto.NoResultsError` if the FormSubmit does not exist.

  ## Examples

      iex> get_form_submit_by_id!("123e4567-e89b-12d3-a456-426614174000")
      %Post{}

      iex> get_form_submit_by_id!("123e4567-e89b-12d3-a456-426614174123")
      ** (Ecto.NoResultsError)

  """
  def get_form_submit_by_id!(id, preload \\ []),
    do: Repo.get_by!(FormSubmit, id: id) |> Repo.preload(preload)

  @doc """
  Gets a single FormSubmit scoped to the given event.

  Returns `nil` if the FormSubmit does not exist or does not belong to the event.
  """
  def get_form_submit_for_event(id, event_id) do
    from(fs in FormSubmit,
      join: f in assoc(fs, :form),
      join: pf in assoc(f, :presentation_file),
      where: fs.id == ^id and pf.event_id == ^event_id
    )
    |> Repo.one()
  end

  @doc """
  Creates or update a FormSubmit.

  ## Examples

      iex> create_or_update_form_submit(%{field: value})
      {:ok, %FormSubmit{}}

      iex> create_or_update_form_submit(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_or_update_form_submit(
        event_uuid,
        %{"user_id" => user_id, "form_id" => form_id} = attrs
      )
      when is_number(user_id) do
    upsert_form_submit(event_uuid, form_id, {:user, user_id}, attrs)
  end

  def create_or_update_form_submit(
        event_uuid,
        %{"attendee_identifier" => attendee_identifier, "form_id" => form_id} = attrs
      ) do
    upsert_form_submit(event_uuid, form_id, {:attendee, attendee_identifier}, attrs)
  end

  def create_or_update_form_submit(_form_submit, event_ref, attrs) do
    case submission_identity(attrs) do
      {:ok, identity} -> upsert_form_submit(event_ref, attr(attrs, "form_id"), identity, attrs)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a form submit.

  ## Examples

      iex> delete_form_submit(post, event_id)
      {:ok, %FormSubmit{}}

      iex> delete_form_submit(post, event_id)
      {:error, %Ecto.Changeset{}}

  """
  def delete_form_submit(event_uuid, %FormSubmit{} = fs) do
    fs
    |> Repo.delete()
    |> case do
      {:ok, r} -> broadcast({:ok, r, event_uuid}, :form_submit_deleted)
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking form submit changes.

  ## Examples

      iex> change_form_submit(form_submit)
      %Ecto.Changeset{data: %FormSubmit{}}

  """
  def change_form_submit(%FormSubmit{} = form_submit, attrs \\ %{}) do
    FormSubmit.changeset(form_submit, attrs)
  end

  def validate_response(%Form{} = form, response) do
    with {:ok, normalized} <- normalize_response(response) do
      fields_by_name = Map.new(form.fields, &{&1.name, &1})
      unknown? = Enum.any?(Map.keys(normalized), &(not Map.has_key?(fields_by_name, &1)))

      errors =
        form.fields
        |> Enum.flat_map(&validate_field(&1, Map.get(normalized, &1.name)))
        |> then(fn errors ->
          if unknown?, do: ["contains an unknown field" | errors], else: errors
        end)

      if errors == [], do: {:ok, normalized}, else: {:error, Enum.reverse(errors)}
    end
  end

  defp upsert_form_submit(event_ref, form_id, identity, attrs) do
    with {:ok, form_id} <- integer_id(form_id),
         %Form{} = form <- form_for_submission(form_id),
         :ok <- validate_event_ref(form, event_ref),
         {:ok, response} <- validate_response(form, attr(attrs, "response")) do
      normalized_attrs =
        attrs
        |> stringify_keys()
        |> Map.put("form_id", form.id)
        |> Map.put("response", response)
        |> Map.merge(identity_string_attrs(identity))

      case persist_form_submit(form, identity, normalized_attrs) do
        {:ok, form_submit, status} ->
          event_uuid = form.presentation_file.event.uuid
          event = if status == :created, do: :form_submit_created, else: :form_submit_updated
          broadcast({:ok, Repo.preload(form_submit, :form), event_uuid}, event)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      nil -> {:error, :interaction_not_found}
      {:error, errors} when is_list(errors) -> invalid_response_changeset(attrs, errors)
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_form_submit(form, identity, attrs) do
    Repo.transaction(fn ->
      from(entry in Form, where: entry.id == ^form.id, lock: "FOR UPDATE") |> Repo.one!()

      existing =
        FormSubmit
        |> where([submit], submit.form_id == ^form.id)
        |> identity_query(identity)
        |> Repo.one()

      changeset = FormSubmit.changeset(existing || %FormSubmit{}, attrs)

      case if(existing, do: Repo.update(changeset), else: Repo.insert(changeset)) do
        {:ok, form_submit} -> {form_submit, if(existing, do: :updated, else: :created)}
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, {form_submit, status}} -> {:ok, form_submit, status}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp invalid_response_changeset(attrs, errors) do
    changeset = FormSubmit.changeset(%FormSubmit{}, stringify_keys(attrs))
    {:error, Enum.reduce(errors, changeset, &Ecto.Changeset.add_error(&2, :response, &1))}
  end

  defp form_for_submission(form_id) do
    Form
    |> where([form], form.id == ^form_id)
    |> preload(presentation_file: :event)
    |> Repo.one()
  end

  defp validate_event_ref(%Form{presentation_file: %{event: event}}, event_ref) do
    if event_ref in [event.id, event.uuid], do: :ok, else: {:error, :event_mismatch}
  end

  defp normalize_response(response) when is_map(response) do
    Enum.reduce_while(response, {:ok, %{}}, fn
      {key, value}, {:ok, normalized} when is_binary(key) ->
        {:cont, {:ok, Map.put(normalized, key, value)}}

      {key, value}, {:ok, normalized} when is_atom(key) ->
        {:cont, {:ok, Map.put(normalized, Atom.to_string(key), value)}}

      _entry, _acc ->
        {:halt, {:error, ["contains an invalid field name"]}}
    end)
  end

  defp normalize_response(_response), do: {:error, ["must be an object"]}

  defp validate_field(%Field{required: true}, value) when value in [nil, ""], do: ["is required"]
  defp validate_field(%Field{required: false}, value) when value in [nil, ""], do: []

  defp validate_field(%Field{type: type}, value) when not is_binary(value),
    do: ["has an invalid value for #{type}"]

  defp validate_field(%Field{type: "text"}, value) do
    if String.length(value) <= 500, do: [], else: ["is too long"]
  end

  defp validate_field(%Field{type: "email"}, value) do
    cond do
      String.length(value) > 254 -> ["is too long"]
      Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, value) -> []
      true -> ["has an invalid email"]
    end
  end

  defp validate_field(%Field{}, _value), do: ["has an unsupported field type"]

  defp submission_identity(attrs) do
    cond do
      is_integer(attr(attrs, "user_id")) ->
        {:ok, {:user, attr(attrs, "user_id")}}

      is_binary(attr(attrs, "attendee_identifier")) ->
        {:ok, {:attendee, attr(attrs, "attendee_identifier")}}

      true ->
        {:error, :invalid_identity}
    end
  end

  defp identity_query(query, {:user, user_id}),
    do: where(query, [submit], submit.user_id == ^user_id)

  defp identity_query(query, {:attendee, attendee_identifier}),
    do: where(query, [submit], submit.attendee_identifier == ^attendee_identifier)

  defp identity_string_attrs({:user, user_id}), do: %{"user_id" => user_id}

  defp identity_string_attrs({:attendee, attendee_identifier}),
    do: %{"attendee_identifier" => attendee_identifier}

  defp integer_id(id) when is_integer(id), do: {:ok, id}

  defp integer_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :interaction_not_found}
    end
  end

  defp integer_id(_id), do: {:error, :interaction_not_found}

  defp attr(attrs, "form_id") when is_map(attrs),
    do: Map.get(attrs, "form_id") || Map.get(attrs, :form_id)

  defp attr(attrs, "user_id") when is_map(attrs),
    do: Map.get(attrs, "user_id") || Map.get(attrs, :user_id)

  defp attr(attrs, "attendee_identifier") when is_map(attrs),
    do: Map.get(attrs, "attendee_identifier") || Map.get(attrs, :attendee_identifier)

  defp attr(attrs, "response") when is_map(attrs),
    do: Map.get(attrs, "response") || Map.get(attrs, :response)

  defp attr(_attrs, _key), do: nil

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      entry -> entry
    end)
  end

  defp stringify_keys(_attrs), do: %{}
end
