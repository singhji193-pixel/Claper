defmodule ClaperWeb.AdminLive.AgendaLive.FormComponent do
  use ClaperWeb, :live_component

  alias Claper.Agendas
  alias Claper.EventApp.Time, as: EventTime

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        id="agenda-item-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        {hidden_input(@form, :position)}

        <div class="grid grid-cols-1 gap-6 md:grid-cols-6">
          <div class="md:col-span-3">
            <label class="label">
              <span class="label-text">{gettext("Event")}</span>
            </label>
            {select(@form, :event_id, @event_options,
              class: "select select-bordered w-full",
              required: true
            )}
            <label class="label">{error_tag(@form, :event_id)}</label>
          </div>

          <div class="md:col-span-3">
            <label class="label">
              <span class="label-text">{gettext("Time")}</span>
            </label>
            {datetime_local_input(@form, :starts_at,
              class: "input input-bordered w-full",
              required: true
            )}
            <label class="label">{error_tag(@form, :starts_at)}</label>
          </div>

          <div class="md:col-span-6">
            <label class="label">
              <span class="label-text">{gettext("Session title")}</span>
            </label>
            {text_input(@form, :title,
              class: "input input-bordered w-full",
              required: true,
              maxlength: 255
            )}
            <label class="label">{error_tag(@form, :title)}</label>
          </div>

          <div class="md:col-span-4">
            <label class="label">
              <span class="label-text">{gettext("Speaker")}</span>
            </label>
            {text_input(@form, :speaker_name,
              class: "input input-bordered w-full",
              maxlength: 255
            )}
            <label class="label">{error_tag(@form, :speaker_name)}</label>
          </div>

          <div class="md:col-span-2">
            <label class="label">
              <span class="label-text">{gettext("Duration")}</span>
            </label>
            {number_input(@form, :duration_minutes,
              class: "input input-bordered w-full",
              min: 1,
              max: 1440
            )}
            <label class="label">{error_tag(@form, :duration_minutes)}</label>
          </div>

          <div class="md:col-span-3">
            <label class="label">
              <span class="label-text">{gettext("Speaker title")}</span>
            </label>
            {text_input(@form, :speaker_title,
              class: "input input-bordered w-full",
              maxlength: 255
            )}
            <label class="label">{error_tag(@form, :speaker_title)}</label>
          </div>

          <div class="md:col-span-3">
            <label class="label">
              <span class="label-text">{gettext("Speaker company")}</span>
            </label>
            {text_input(@form, :speaker_company,
              class: "input input-bordered w-full",
              maxlength: 255
            )}
            <label class="label">{error_tag(@form, :speaker_company)}</label>
          </div>

          <div class="md:col-span-2">
            <label class="label">
              <span class="label-text">{gettext("Track")}</span>
            </label>
            {text_input(@form, :track_name,
              class: "input input-bordered w-full",
              maxlength: 120
            )}
            <label class="label">{error_tag(@form, :track_name)}</label>
          </div>

          <div class="md:col-span-2">
            <label class="label">
              <span class="label-text">{gettext("Type")}</span>
            </label>
            {text_input(@form, :session_type,
              class: "input input-bordered w-full",
              maxlength: 120
            )}
            <label class="label">{error_tag(@form, :session_type)}</label>
          </div>

          <div class="md:col-span-2">
            <label class="label">
              <span class="label-text">{gettext("Location")}</span>
            </label>
            {text_input(@form, :location_name,
              class: "input input-bordered w-full",
              maxlength: 255
            )}
            <label class="label">{error_tag(@form, :location_name)}</label>
          </div>

          <div class="md:col-span-6">
            <label class="label">
              <span class="label-text">{gettext("Description")}</span>
            </label>
            {textarea(@form, :description,
              class: "textarea textarea-bordered w-full",
              rows: 4
            )}
            <label class="label">{error_tag(@form, :description)}</label>
          </div>
        </div>

        <div class="mt-6 flex justify-end gap-3">
          <button type="button" phx-click="cancel" phx-target={@myself} class="btn btn-ghost">
            {gettext("Cancel")}
          </button>
          <button type="submit" phx-disable-with={gettext("Saving...")} class="btn btn-primary">
            {if @action == :new,
              do: gettext("Create agenda item"),
              else: gettext("Update agenda item")}
          </button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{agenda_item: agenda_item} = assigns, socket) do
    timezone = assigns[:timezone]

    changeset =
      Agendas.change_agenda_item(%{
        agenda_item
        | starts_at: EventTime.to_local(agenda_item.starts_at, timezone)
      })

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"agenda_item" => agenda_item_params}, socket) do
    changeset =
      socket.assigns.agenda_item
      |> Agendas.change_agenda_item(convert_params(agenda_item_params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"agenda_item" => agenda_item_params}, socket) do
    save_agenda_item(socket, socket.assigns.action, convert_params(agenda_item_params, socket))
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.navigate)}
  end

  defp save_agenda_item(socket, :new, agenda_item_params) do
    case Agendas.create_agenda_item(agenda_item_params) do
      {:ok, agenda_item} ->
        notify_parent({:saved, agenda_item})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Agenda item saved successfully"))
         |> push_navigate(to: saved_path(socket, agenda_item))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_agenda_item(socket, :edit, agenda_item_params) do
    case Agendas.update_agenda_item(socket.assigns.agenda_item, agenda_item_params) do
      {:ok, agenda_item} ->
        notify_parent({:saved, agenda_item})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Agenda item saved successfully"))
         |> push_navigate(to: saved_path(socket, agenda_item))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp convert_params(params, socket) do
    EventTime.convert_starts_at_param(params, socket.assigns[:timezone])
  end

  defp saved_path(socket, agenda_item) do
    socket.assigns[:navigate_after_save] || ~p"/admin/agenda?event_id=#{agenda_item.event_id}"
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
