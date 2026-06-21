defmodule ClaperWeb.PwaLive.LiveInteractionsComponent do
  use ClaperWeb, :live_component

  import ClaperWeb.PwaLive.App, only: [ngs_icon: 1]

  alias Claper.EventApp.LiveInteractions
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:active_tab, fn -> :interact end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      class="ngs-live-shell"
      phx-disconnected={JS.show(to: "#live-reconnect")}
      phx-connected={JS.hide(to: "#live-reconnect")}
    >
      <div id="live-reconnect" class="ngs-live-reconnect" role="status" style="display: none;">
        <.ngs_icon name="hero-arrow-path" class="size-5" />
        <span>{gettext("Reconnecting before answers can be submitted...")}</span>
      </div>

      <nav class="ngs-live-tabs" aria-label={gettext("Live session views")}>
        <button
          :for={{tab, label} <- live_tabs(@snapshot)}
          type="button"
          phx-click="live-tab"
          phx-value-tab={tab}
          phx-target={@myself}
          class={["ngs-live-tab ngs-focus", @active_tab == tab && "is-active"]}
          aria-current={@active_tab == tab && "page"}
        >
          {label}
        </button>
      </nav>

      <div :if={@snapshot && @snapshot.banned} class="ngs-live-notice is-error" role="alert">
        <.ngs_icon name="hero-no-symbol" class="size-5" />
        <div>
          <strong>{gettext("Live participation unavailable")}</strong>
          <p>{gettext("An organizer has disabled interaction access for this attendee.")}</p>
        </div>
      </div>

      <%= case @active_tab do %>
        <% :interact -> %>
          <.interaction_panel
            snapshot={@snapshot}
            event={@event}
            interaction_key={@interaction_key}
            myself={@myself}
          />
        <% :qa -> %>
          <.posts_panel
            enabled={@snapshot && @snapshot.qa_enabled}
            posts={if @snapshot, do: @snapshot.questions, else: []}
            kind="question"
            icon="hero-question-mark-circle"
            title={gettext("Session Q&A")}
            unavailable={gettext("Q&A is not enabled for this event.")}
            snapshot={@snapshot}
            myself={@myself}
          />
        <% :chat -> %>
          <.posts_panel
            enabled={@snapshot && @snapshot.chat_enabled}
            posts={if @snapshot, do: @snapshot.messages, else: []}
            kind="message"
            icon="hero-chat-bubble-left-right"
            title={gettext("Session chat")}
            unavailable={gettext("Chat is not open right now.")}
            snapshot={@snapshot}
            myself={@myself}
          />
      <% end %>
    </section>
    """
  end

  attr :snapshot, :map, default: nil
  attr :event, :map, required: true
  attr :interaction_key, :string, default: nil
  attr :myself, :any, required: true

  defp interaction_panel(assigns) do
    ~H"""
    <div class="ngs-live-panel">
      <%= cond do %>
        <% is_nil(@snapshot) -> %>
          <.live_empty
            icon="hero-signal-slash"
            title={gettext("Live state unavailable")}
            body={gettext("Reconnect to check the current session interaction.")}
          />
        <% !@snapshot.enabled -> %>
          <.live_empty
            icon="hero-lock-closed"
            title={gettext("Live interactions are not open")}
            body={gettext("The organizer has not enabled this feature for attendees yet.")}
          />
        <% @snapshot.banned -> %>
          <.live_empty
            icon="hero-no-symbol"
            title={gettext("Participation unavailable")}
            body={gettext("You can continue using Agenda, People, Bingo, and Profile.")}
          />
        <% @snapshot.active -> %>
          <.active_interaction interaction={@snapshot.active} myself={@myself} />
        <% @snapshot.latest_result -> %>
          <div>
            <p class="ngs-eyebrow">{gettext("Latest result")}</p>
            <.active_interaction interaction={@snapshot.latest_result} myself={@myself} closed />
          </div>
        <% true -> %>
          <.live_empty
            icon="hero-bolt"
            title={gettext("Nothing live right now")}
            body={gettext("Keep this screen open. It will update when the presenter starts.")}
          />
      <% end %>
    </div>
    """
  end

  attr :interaction, :map, required: true
  attr :myself, :any, required: true
  attr :closed, :boolean, default: false

  defp active_interaction(%{interaction: %{kind: :poll}} = assigns) do
    submitted? = assigns.interaction.submitted_option_ids != [] or assigns.closed
    assigns = assign(assigns, :submitted?, submitted?)

    ~H"""
    <article class="ngs-live-card" id={"live-poll-#{@interaction.id}"}>
      <header>
        <span class="ngs-live-kind">
          <.ngs_icon name="hero-chart-bar" class="size-4" /> {gettext("Poll")}
        </span>
        <span :if={@submitted?} class="ngs-live-status">
          <.ngs_icon name="hero-check-circle" class="size-4" />
          {if @closed, do: gettext("Closed"), else: gettext("Submitted")}
        </span>
      </header>
      <h2>{@interaction.title}</h2>
      <p :if={!@submitted? && @interaction.multiple} class="ngs-live-help">
        {gettext("Select one or more answers.")}
      </p>

      <form
        id={"pwa-live-poll-form-#{@interaction.id}"}
        phx-submit="live-vote-poll"
        phx-target={@myself}
        class="ngs-live-options"
      >
        <input type="hidden" name="poll_id" value={@interaction.id} />
        <label
          :for={option <- @interaction.options}
          class={[
            "ngs-live-option",
            option.id in @interaction.submitted_option_ids && "is-selected"
          ]}
        >
          <input
            type={if @interaction.multiple, do: "checkbox", else: "radio"}
            name="option_ids[]"
            value={option.id}
            checked={option.id in @interaction.submitted_option_ids}
            disabled={@submitted?}
          />
          <span>{option.content}</span>
          <strong :if={Map.has_key?(option, :vote_count)}>{option.percentage}%</strong>
        </label>

        <button
          :if={!@submitted?}
          type="submit"
          phx-disable-with={gettext("Submitting...")}
          class="ngs-button ngs-button-primary ngs-focus"
        >
          {gettext("Submit answer")}
        </button>
      </form>
    </article>
    """
  end

  defp active_interaction(%{interaction: %{kind: :quiz}} = assigns) do
    ~H"""
    <article class="ngs-live-card" id={"live-quiz-#{@interaction.id}"}>
      <header>
        <span class="ngs-live-kind">
          <.ngs_icon name="hero-light-bulb" class="size-4" /> {gettext("Quiz")}
        </span>
        <span :if={@closed} class="ngs-live-status">{gettext("Closed")}</span>
      </header>
      <h2>{@interaction.title}</h2>

      <section
        :for={{question, index} <- Enum.with_index(@interaction.questions)}
        class="ngs-live-question"
      >
        <% locked = question_submitted?(question, @interaction.submitted_option_ids) || @closed %>
        <p class="ngs-eyebrow">{gettext("Question %{number}", number: index + 1)}</p>
        <h3>{question.content}</h3>
        <form
          id={"pwa-live-quiz-form-#{@interaction.id}-#{question.id}"}
          phx-submit="live-submit-quiz"
          phx-target={@myself}
          class="ngs-live-options"
        >
          <input type="hidden" name="quiz_id" value={@interaction.id} />
          <label
            :for={option <- question.options}
            class={[
              "ngs-live-option",
              option.id in @interaction.submitted_option_ids && "is-selected",
              option[:is_correct] == true && "is-correct"
            ]}
          >
            <input
              type="checkbox"
              name="option_ids[]"
              value={option.id}
              checked={option.id in @interaction.submitted_option_ids}
              disabled={locked}
            />
            <span>{option.content}</span>
            <strong :if={Map.has_key?(option, :response_count)}>{option.response_count}</strong>
          </label>
          <button
            :if={!locked}
            type="submit"
            phx-disable-with={gettext("Submitting...")}
            class="ngs-button ngs-button-primary ngs-focus"
          >
            {gettext("Lock answer")}
          </button>
        </form>
      </section>
    </article>
    """
  end

  defp active_interaction(%{interaction: %{kind: :form}} = assigns) do
    ~H"""
    <article class="ngs-live-card" id={"live-form-#{@interaction.id}"}>
      <header>
        <span class="ngs-live-kind">
          <.ngs_icon name="hero-document-text" class="size-4" /> {gettext("Form")}
        </span>
        <span :if={@interaction.submitted} class="ngs-live-status">
          <.ngs_icon name="hero-check-circle" class="size-4" /> {gettext("Saved")}
        </span>
      </header>
      <h2>{@interaction.title}</h2>
      <form
        id={"pwa-live-form-#{@interaction.id}"}
        phx-submit="live-submit-form"
        phx-target={@myself}
        class="ngs-live-fields"
      >
        <input type="hidden" name="form_id" value={@interaction.id} />
        <label :for={field <- @interaction.fields}>
          <span>{field.name}</span>
          <input
            type={field.type}
            name={"response[#{field.name}]"}
            value={Map.get(@interaction.response, field.name, "")}
            required={field.required}
            maxlength={if field.type == "email", do: 254, else: 500}
          />
        </label>
        <button
          type="submit"
          phx-disable-with={gettext("Saving...")}
          class="ngs-button ngs-button-primary ngs-focus"
        >
          {if @interaction.submitted, do: gettext("Update response"), else: gettext("Submit response")}
        </button>
      </form>
    </article>
    """
  end

  defp active_interaction(%{interaction: %{kind: :embed}} = assigns) do
    ~H"""
    <article class="ngs-live-card" id={"live-embed-#{@interaction.id}"}>
      <header>
        <span class="ngs-live-kind">
          <.ngs_icon name="hero-play-circle" class="size-4" /> {gettext("Live content")}
        </span>
      </header>
      <h2>{@interaction.title}</h2>
      <div :if={@interaction.inline} class="ngs-live-embed">
        <iframe
          src={@interaction.url}
          title={@interaction.title}
          loading="lazy"
          referrerpolicy="strict-origin-when-cross-origin"
          sandbox="allow-scripts allow-same-origin allow-presentation allow-popups"
          allow="autoplay; fullscreen; picture-in-picture"
          allowfullscreen
        >
        </iframe>
      </div>
      <a
        :if={!@interaction.inline}
        href={@interaction.url}
        target="_blank"
        rel="noopener noreferrer"
        class="ngs-button ngs-button-primary ngs-focus"
      >
        {gettext("Open content")}
      </a>
    </article>
    """
  end

  defp active_interaction(assigns) do
    ~H"""
    <.live_empty
      icon="hero-link"
      title={@interaction.title}
      body={gettext("This content will open when its safe attendee view is available.")}
    />
    """
  end

  attr :enabled, :boolean, default: false
  attr :posts, :list, default: []
  attr :kind, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :unavailable, :string, required: true
  attr :snapshot, :map, default: nil
  attr :myself, :any, required: true

  defp posts_panel(assigns) do
    ~H"""
    <%= if @enabled do %>
      <section class="ngs-live-posts">
        <header class="ngs-live-posts-header">
          <span><.ngs_icon name={@icon} class="size-5" /></span>
          <div>
            <h2>{@title}</h2>
            <p>{post_count_label(@posts, @kind)}</p>
          </div>
        </header>

        <form
          id={"pwa-live-#{@kind}-form"}
          phx-submit="live-create-post"
          phx-target={@myself}
          class="ngs-live-compose"
        >
          <input type="hidden" name="kind" value={@kind} />
          <label>
            <span class="sr-only">{post_placeholder(@kind)}</span>
            <textarea
              name="body"
              required
              minlength="2"
              maxlength="255"
              placeholder={post_placeholder(@kind)}
            ></textarea>
          </label>
          <label :if={@snapshot && @snapshot.state.anonymous_chat_enabled} class="ngs-live-anonymous">
            <input type="checkbox" name="anonymous" value="true" />
            <span>{gettext("Post anonymously")}</span>
          </label>
          <button
            type="submit"
            phx-disable-with={gettext("Posting...")}
            class="ngs-button ngs-button-primary ngs-focus"
          >
            {if @kind == "question", do: gettext("Ask question"), else: gettext("Send message")}
          </button>
        </form>

        <div
          :if={@kind == "message"}
          class="ngs-live-global-reactions"
          aria-label={gettext("Room reactions")}
        >
          <button
            :for={
              {type, label} <- [
                {"heart", "Heart"},
                {"clap", "Clap"},
                {"hundred", "100"},
                {"raisehand", "Raise hand"}
              ]
            }
            type="button"
            phx-click="live-global-reaction"
            phx-value-type={type}
            phx-target={@myself}
            class="ngs-focus"
            aria-label={label}
          >
            <.ngs_icon name={global_reaction_icon(type)} class="size-5" />
          </button>
        </div>

        <div class="ngs-live-post-list">
          <article :for={post <- @posts} id={"pwa-live-post-#{post.uuid}"} class="ngs-live-post">
            <header>
              <strong>{post.name}</strong>
              <span :if={post.pinned}>
                <.ngs_icon name="hero-bookmark" class="size-4" /> {gettext("Pinned")}
              </span>
            </header>
            <p>{post.body}</p>
            <div class="ngs-live-post-actions">
              <button
                type="button"
                phx-click="live-toggle-reaction"
                phx-value-post-id={post.uuid}
                phx-value-icon="👍"
                phx-target={@myself}
                class={["ngs-focus", post.reacted && "is-active"]}
                aria-pressed={post.reacted}
              >
                <.ngs_icon name="hero-hand-thumb-up" class="size-4" />
                <span>{post.like_count}</span>
              </button>
              <span :if={@kind == "message"}>
                <.ngs_icon name="hero-heart" class="size-4" /> {post.love_count}
              </span>
              <span :if={@kind == "message"}>
                <.ngs_icon name="hero-face-smile" class="size-4" /> {post.lol_count}
              </span>
            </div>
          </article>
        </div>

        <.live_empty
          :if={Enum.empty?(@posts)}
          icon={@icon}
          title={
            if @kind == "question", do: gettext("No questions yet"), else: gettext("Chat is quiet")
          }
          body={
            if @kind == "question",
              do: gettext("Ask the first question for this session."),
              else: gettext("Start a useful conversation with the room.")
          }
        />
      </section>
    <% else %>
      <.live_empty icon={@icon} title={@title} body={@unavailable} />
    <% end %>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true

  defp live_empty(assigns) do
    ~H"""
    <section class="ngs-live-empty">
      <span><.ngs_icon name={@icon} class="size-7" /></span>
      <h2>{@title}</h2>
      <p>{@body}</p>
    </section>
    """
  end

  @impl true
  def handle_event("live-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab_atom(tab))}
  end

  def handle_event("live-vote-poll", params, socket) do
    submit_interaction(socket, fn ->
      LiveInteractions.vote_poll(
        socket.assigns.event,
        socket.assigns.interaction_key,
        integer(params["poll_id"]),
        params["option_ids"] || []
      )
    end)
  end

  def handle_event("live-submit-quiz", params, socket) do
    submit_interaction(socket, fn ->
      LiveInteractions.submit_quiz(
        socket.assigns.event,
        socket.assigns.interaction_key,
        integer(params["quiz_id"]),
        params["option_ids"] || []
      )
    end)
  end

  def handle_event("live-submit-form", params, socket) do
    submit_interaction(socket, fn ->
      LiveInteractions.submit_form(
        socket.assigns.event,
        socket.assigns.interaction_key,
        integer(params["form_id"]),
        params["response"] || %{}
      )
    end)
  end

  def handle_event("live-create-post", params, socket) do
    anonymous = params["anonymous"] == "true"

    case LiveInteractions.create_post(
           socket.assigns.event,
           socket.assigns.interaction_key,
           params["kind"],
           params["body"],
           anonymous
         ) do
      {:ok, _post, _settings} -> refresh_snapshot(socket)
      {:error, reason} -> interaction_error(socket, reason)
    end
  end

  def handle_event("live-toggle-reaction", params, socket) do
    case LiveInteractions.toggle_reaction(
           socket.assigns.event,
           socket.assigns.interaction_key,
           params["post-id"],
           params["icon"]
         ) do
      {:ok, _status, _post} -> refresh_snapshot(socket)
      {:error, reason} -> interaction_error(socket, reason)
    end
  end

  def handle_event("live-global-reaction", %{"type" => type}, socket) do
    case LiveInteractions.global_reaction(
           socket.assigns.event,
           socket.assigns.interaction_key,
           global_reaction_type(type)
         ) do
      :ok -> {:noreply, socket}
      {:error, reason} -> interaction_error(socket, reason)
    end
  end

  defp submit_interaction(socket, callback) do
    case callback.() do
      {:ok, snapshot} ->
        send(self(), {:pwa_live_snapshot, snapshot})
        {:noreply, assign(socket, :snapshot, snapshot)}

      {:error, reason} ->
        send(self(), {:pwa_live_error, reason})
        {:noreply, socket}
    end
  end

  defp refresh_snapshot(socket) do
    case LiveInteractions.snapshot(socket.assigns.event, socket.assigns.interaction_key) do
      {:ok, snapshot} ->
        send(self(), {:pwa_live_snapshot, snapshot})
        {:noreply, assign(socket, :snapshot, snapshot)}

      {:error, reason} ->
        interaction_error(socket, reason)
    end
  end

  defp interaction_error(socket, reason) do
    send(self(), {:pwa_live_error, reason})
    {:noreply, socket}
  end

  defp live_tabs(snapshot) do
    base = [{:interact, gettext("Interact")}, {:qa, gettext("Q&A")}, {:chat, gettext("Chat")}]

    Enum.filter(base, fn
      {:interact, _label} -> true
      {:qa, _label} -> snapshot && snapshot.qa_enabled
      {:chat, _label} -> snapshot && snapshot.chat_enabled
    end)
  end

  defp question_submitted?(question, submitted_ids) do
    Enum.any?(question.options, &(&1.id in submitted_ids))
  end

  defp tab_atom("qa"), do: :qa
  defp tab_atom("chat"), do: :chat
  defp tab_atom(_tab), do: :interact

  defp post_count_label(posts, "question"),
    do: ngettext("1 question", "%{count} questions", length(posts))

  defp post_count_label(posts, _kind),
    do: ngettext("1 message", "%{count} messages", length(posts))

  defp post_placeholder("question"), do: gettext("Ask a clear question")
  defp post_placeholder(_kind), do: gettext("Message the room")

  defp global_reaction_type("heart"), do: :heart
  defp global_reaction_type("clap"), do: :clap
  defp global_reaction_type("hundred"), do: :hundred
  defp global_reaction_type("raisehand"), do: :raisehand
  defp global_reaction_type(_type), do: :invalid

  defp global_reaction_icon("heart"), do: "hero-heart"
  defp global_reaction_icon("clap"), do: "hero-sparkles"
  defp global_reaction_icon("hundred"), do: "hero-fire"
  defp global_reaction_icon("raisehand"), do: "hero-hand-raised"

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer(_value), do: nil
end
