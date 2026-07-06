defmodule ClaperWeb.PwaLive.LiveInteractionsComponent do
  use ClaperWeb, :live_component

  import ClaperWeb.PwaLive.App, only: [ngs_icon: 1]

  alias Claper.EventApp.LiveInteractions
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    previous_snapshot = socket.assigns[:snapshot]

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:active_tab, fn -> :interact end)
     |> maybe_jump_to_interact(previous_snapshot)
     |> track_unread()}
  end

  # A fresh presenter activation pulls the attendee to Interact so nobody
  # has to know where to navigate. Manual tab choices are only overridden
  # when a genuinely new interaction starts.
  defp maybe_jump_to_interact(socket, previous_snapshot) do
    new_ref = active_ref(socket.assigns[:snapshot])

    if previous_snapshot != nil and new_ref != nil and
         new_ref != active_ref(previous_snapshot) do
      assign(socket, :active_tab, :interact)
    else
      socket
    end
  end

  defp active_ref(%{active: %{} = active}),
    do: {Map.get(active, :kind), Map.get(active, :id) || Map.get(active, :title)}

  defp active_ref(_snapshot), do: nil

  # Posts arriving while another tab is open flag that tab with a dot; the
  # count is marked seen the moment the tab is visited.
  defp track_unread(socket) do
    snapshot = socket.assigns[:snapshot]
    counts = %{qa: tab_count(snapshot, :qa), chat: tab_count(snapshot, :chat)}
    seen = socket.assigns[:seen_counts] || counts
    seen = mark_seen(seen, socket.assigns.active_tab, counts)

    socket
    |> assign(:seen_counts, seen)
    |> assign(:unread_tabs, %{
      qa: counts.qa > Map.get(seen, :qa, 0),
      chat: counts.chat > Map.get(seen, :chat, 0)
    })
  end

  defp mark_seen(seen, :qa, counts), do: Map.put(seen, :qa, counts.qa)
  defp mark_seen(seen, :chat, counts), do: Map.put(seen, :chat, counts.chat)
  defp mark_seen(seen, _tab, _counts), do: seen

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

      <h1 class="sr-only">{gettext("Live")}</h1>

      <nav class="ngs-live-tabs" aria-label={gettext("Live session views")}>
        <span class={[
          "ngs-live-badge is-inline",
          !(@snapshot && @snapshot.active) && "is-idle"
        ]}>
          <span class="ngs-live-pulse" aria-hidden="true"></span>
          {gettext("Live")}
        </span>
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
          <span :if={tab_count(@snapshot, tab) > 0} class="ngs-tab-count">
            {tab_count(@snapshot, tab)}
          </span>
          <span :if={unread_tab?(@unread_tabs, tab)} class="ngs-tab-dot">
            <span class="sr-only">{gettext("new activity")}</span>
          </span>
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
            timezone={assigns[:timezone]}
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
            timezone={assigns[:timezone]}
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
            body={
              gettext(
                "Q&A and Chat stay open in the tabs above. This view jumps in the moment the presenter starts a poll or quiz."
              )
            }
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
            option.id in @interaction.submitted_option_ids && "is-selected",
            Map.has_key?(option, :vote_count) && "has-results"
          ]}
        >
          <span
            :if={Map.has_key?(option, :vote_count)}
            class="ngs-live-bar"
            style={"--ngs-bar: #{option.percentage}%"}
            aria-hidden="true"
          >
          </span>
          <input
            type={if @interaction.multiple, do: "checkbox", else: "radio"}
            name="option_ids[]"
            value={option.id}
            checked={option.id in @interaction.submitted_option_ids}
            disabled={@submitted?}
          />
          <span>{option.content}</span>
          <.ngs_icon
            :if={option.id in @interaction.submitted_option_ids}
            name="hero-check-circle"
            class="size-4 ngs-live-option-check"
          />
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
  attr :timezone, :string, default: nil
  attr :myself, :any, required: true

  defp posts_panel(assigns) do
    ~H"""
    <%= if @enabled do %>
      <section class={["ngs-live-posts", "is-#{@kind}"]}>
        <h2 class="sr-only">{@title}</h2>
        <p class="ngs-live-posts-count">{post_count_label(@posts, @kind)}</p>

        <div
          class="ngs-live-posts-scroll"
          id={"pwa-live-post-scroll-#{@kind}"}
          phx-hook={if @kind == "message", do: "ScrollBottom"}
        >
          <div class="ngs-live-post-list" role="list">
            <article
              :for={post <- @posts}
              id={"pwa-live-post-#{post.uuid}"}
              class={["ngs-live-post", @kind == "message" && post[:mine] && "is-mine"]}
              role="listitem"
            >
              <span
                :if={@kind == "question" or !post[:mine]}
                class="ngs-post-avatar"
                aria-hidden="true"
              >
                {post_initials(post.name)}
              </span>
              <div class="ngs-live-post-bubble">
                <header>
                  <strong>
                    {if @kind == "message" && post[:mine], do: gettext("You"), else: post.name}
                  </strong>
                  <span :if={post.pinned} class="ngs-post-pinned">
                    <.ngs_icon name="hero-bookmark" class="size-4" /> {gettext("Pinned")}
                  </span>
                  <time :if={post[:inserted_at]} class="ngs-post-time">
                    {post_time(post.inserted_at, @timezone)}
                  </time>
                </header>
                <p>{post.body}</p>
                <div
                  :if={@snapshot && @snapshot.state.message_reaction_enabled}
                  class="ngs-live-post-actions"
                >
                  <button
                    type="button"
                    phx-click="live-toggle-reaction"
                    phx-value-post-id={post.uuid}
                    phx-value-icon="👍"
                    phx-target={@myself}
                    class={["ngs-focus is-like", post.liked && "is-active"]}
                    aria-label={gettext("Like")}
                    aria-pressed={post.liked}
                  >
                    <img src="/images/icons/thumb.svg" alt="" class="ngs-live-post-action-icon" />
                    <span :if={post.like_count > 0}>{post.like_count}</span>
                  </button>
                  <button
                    :if={@kind == "message"}
                    type="button"
                    phx-click="live-toggle-reaction"
                    phx-value-post-id={post.uuid}
                    phx-value-icon="❤️"
                    phx-target={@myself}
                    class={["ngs-focus is-heart", post.loved && "is-active"]}
                    aria-label={gettext("Heart")}
                    aria-pressed={post.loved}
                  >
                    <img src="/images/icons/heart.svg" alt="" class="ngs-live-post-action-icon" />
                    <span :if={post.love_count > 0}>{post.love_count}</span>
                  </button>
                  <button
                    :if={@kind == "message"}
                    type="button"
                    phx-click="live-toggle-reaction"
                    phx-value-post-id={post.uuid}
                    phx-value-icon="😂"
                    phx-target={@myself}
                    class={["ngs-focus is-laugh", post.laughed && "is-active"]}
                    aria-label={gettext("Laugh")}
                    aria-pressed={post.laughed}
                  >
                    <img src="/images/icons/laugh.svg" alt="" class="ngs-live-post-action-icon" />
                    <span :if={post.lol_count > 0}>{post.lol_count}</span>
                  </button>
                </div>
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
        </div>

        <div class="ngs-live-posts-composer" aria-label={post_placeholder(@kind)}>
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
              <img src={global_reaction_asset(type)} alt="" class="ngs-live-reaction-img" />
            </button>
          </div>

          <form
            id={"pwa-live-#{@kind}-form"}
            phx-submit="live-create-post"
            phx-target={@myself}
            class="ngs-live-compose"
          >
            <input type="hidden" name="kind" value={@kind} />
            <label class="ngs-live-compose-field">
              <span class="sr-only">{post_placeholder(@kind)}</span>
              <textarea
                name="body"
                required
                minlength="2"
                maxlength="255"
                placeholder={post_placeholder(@kind)}
              ></textarea>
            </label>
            <label
              :if={@snapshot && @snapshot.state.anonymous_chat_enabled}
              class="ngs-live-anonymous"
            >
              <input type="checkbox" name="anonymous" value="true" />
              <span>{gettext("Post anonymously")}</span>
            </label>
            <button
              type="submit"
              phx-disable-with={gettext("Posting...")}
              class="ngs-live-send ngs-focus"
              aria-label={
                if @kind == "question", do: gettext("Ask question"), else: gettext("Send message")
              }
            >
              <img src="/images/icons/send.svg" alt="" />
              <span>{if @kind == "question", do: gettext("Ask"), else: gettext("Send")}</span>
            </button>
          </form>
        </div>
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
    {:noreply,
     socket
     |> assign(:active_tab, tab_atom(tab))
     |> track_unread()}
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

  defp tab_count(nil, _tab), do: 0
  defp tab_count(snapshot, :qa), do: length(snapshot.questions)
  defp tab_count(snapshot, :chat), do: length(snapshot.messages)
  defp tab_count(_snapshot, _tab), do: 0

  defp unread_tab?(unread_tabs, tab) when is_map(unread_tabs),
    do: Map.get(unread_tabs, tab, false)

  defp unread_tab?(_unread_tabs, _tab), do: false

  defp post_initials(name) when is_binary(name) and name != "" do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp post_initials(_name), do: "A"

  defp post_time(%NaiveDateTime{} = inserted_at, timezone) do
    inserted_at
    |> Claper.EventApp.Time.to_local(timezone)
    |> Calendar.strftime("%H:%M")
  end

  defp post_time(_inserted_at, _timezone), do: nil

  defp global_reaction_type("heart"), do: :heart
  defp global_reaction_type("clap"), do: :clap
  defp global_reaction_type("hundred"), do: :hundred
  defp global_reaction_type("raisehand"), do: :raisehand
  defp global_reaction_type(_type), do: :invalid

  defp global_reaction_asset("heart"), do: "/images/icons/heart.svg"
  defp global_reaction_asset("clap"), do: "/images/icons/clap.svg"
  defp global_reaction_asset("hundred"), do: "/images/icons/hundred.svg"
  defp global_reaction_asset("raisehand"), do: "/images/icons/raisehand.svg"

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp integer(_value), do: nil
end
