defmodule Claper.EventApp.LiveInteractions do
  @moduledoc """
  Event-scoped adapter between the Claper live engine and the attendee PWA.

  PubSub is treated as an invalidation channel. Every snapshot is rebuilt from
  presentation state and persisted interaction records.
  """

  alias Claper.{Events, Forms, Interactions, Polls, Posts, Presentations, Quizzes, RateLimit}
  alias Claper.Embeds.Embed
  alias Claper.EventApp
  alias Claper.EventApp.Setting
  alias Claper.Events.Event
  alias Claper.Forms.Form
  alias Claper.Polls.Poll
  alias Claper.Quizzes.Quiz

  def summary(%Event{} = event, %Setting{live_interactions_enabled: true}) do
    case current_context(event) do
      {:ok, %{active: interaction}} when not is_nil(interaction) ->
        %{
          active: true,
          route: "/app/#{event.code}/live",
          title: interaction.title,
          type: interaction_type(interaction)
        }

      _ ->
        disabled_summary(event)
    end
  end

  def summary(%Event{} = event, _settings), do: disabled_summary(event)

  def snapshot(%Event{} = event, interaction_key) do
    with {:ok, context} <- current_context(event) do
      settings = EventApp.settings_for_event(context.event.id)

      {:ok,
       %{
         enabled: settings.live_interactions_enabled,
         qa_enabled: settings.qa_enabled,
         chat_enabled: settings.chat_enabled and context.state.chat_enabled,
         resources_enabled: settings.resources_enabled,
         banned: banned?(context.state, interaction_key),
         state: public_state(context.state),
         active: public_interaction(context.active, interaction_key),
         latest_result: latest_result(context, interaction_key),
         questions: public_posts(context, interaction_key, "question", settings.qa_enabled),
         messages:
           public_posts(
             context,
             interaction_key,
             "message",
             settings.chat_enabled and context.state.chat_enabled
           )
       }}
    end
  end

  def vote_poll(%Event{} = event, interaction_key, poll_id, option_ids) do
    with {:ok, context} <- authorized_context(event, interaction_key),
         %Poll{id: ^poll_id} <- context.active,
         {:ok, _poll} <- Polls.vote(interaction_key, context.event.uuid, option_ids, poll_id) do
      snapshot(context.event, interaction_key)
    else
      %_{} -> {:error, :interaction_mismatch}
      nil -> {:error, :interaction_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit_quiz(%Event{} = event, interaction_key, quiz_id, option_ids) do
    with {:ok, context} <- authorized_context(event, interaction_key),
         %Quiz{id: ^quiz_id} <- context.active,
         {:ok, _quiz} <-
           Quizzes.submit_quiz(interaction_key, context.event.uuid, option_ids, quiz_id) do
      snapshot(context.event, interaction_key)
    else
      %_{} -> {:error, :interaction_mismatch}
      nil -> {:error, :interaction_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  def submit_form(%Event{} = event, interaction_key, form_id, response) do
    with {:ok, context} <- authorized_context(event, interaction_key),
         %Form{id: ^form_id} <- context.active,
         {:ok, _submit} <-
           Forms.create_or_update_form_submit(context.event.uuid, %{
             "attendee_identifier" => interaction_key,
             "form_id" => form_id,
             "response" => response
           }) do
      snapshot(context.event, interaction_key)
    else
      %_{} -> {:error, :interaction_mismatch}
      nil -> {:error, :interaction_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_post(event, interaction_key, kind, body, anonymous \\ false)

  def create_post(%Event{} = event, interaction_key, kind, body, anonymous)
      when kind in ["question", "message"] do
    with {:ok, context, settings} <- post_context(event, interaction_key, kind),
         :ok <- rate_limit(:post, context.event.id, interaction_key, 5),
         attendee when not is_nil(attendee) <-
           EventApp.get_attendee_by_interaction_key(context.event.id, interaction_key),
         {:ok, post} <-
           Posts.create_post(context.event, %{
             body: body,
             attendee_identifier: interaction_key,
             kind: kind,
             name: post_name(attendee, anonymous, context.state),
             position: context.state.position
           }) do
      {:ok, post, settings}
    else
      nil -> {:error, :invalid_identity}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_post(_event, _interaction_key, _kind, _body, _anonymous),
    do: {:error, :invalid_post_kind}

  def toggle_reaction(%Event{} = event, interaction_key, post_uuid, icon) do
    with {:ok, context} <- participant_context(event, interaction_key),
         :ok <- rate_limit(:reaction, context.event.id, interaction_key, 60),
         {:ok, status, post} <-
           Posts.toggle_attendee_reaction(context.event.id, interaction_key, post_uuid, icon) do
      {:ok, status, post}
    end
  end

  def global_reaction(%Event{} = event, interaction_key, type)
      when type in [:heart, :clap, :hundred, :raisehand] do
    with {:ok, context} <- participant_context(event, interaction_key),
         :ok <- rate_limit(:global_reaction, context.event.id, interaction_key, 30) do
      Phoenix.PubSub.broadcast(
        Claper.PubSub,
        "event:#{context.event.uuid}",
        {:react, type}
      )

      :ok
    end
  end

  def global_reaction(_event, _interaction_key, _type), do: {:error, :invalid_reaction}

  def subscribe(%Event{} = event) do
    with {:ok, context} <- current_context(event) do
      Events.Event.subscribe(context.event.uuid)
      Presentations.subscribe(context.event.presentation_file.id)
      :ok
    end
  end

  def invalidation_message?({event, _payload})
      when event in [
             :state_updated,
             :page_changed,
             :current_interaction,
             :poll_created,
             :poll_updated,
             :poll_deleted,
             :quiz_created,
             :quiz_updated,
             :quiz_deleted,
             :form_created,
             :form_updated,
             :form_deleted,
             :embed_created,
             :embed_updated,
             :embed_deleted,
             :post_created,
             :post_updated,
             :post_deleted,
             :post_pinned,
             :post_unpinned,
             :reaction_added,
             :reaction_removed,
             :banned
           ],
      do: true

  def invalidation_message?(_message), do: false

  defp authorized_context(%Event{} = event, interaction_key)
       when is_binary(interaction_key) and byte_size(interaction_key) > 0 do
    with {:ok, context} <- current_context(event),
         %Setting{live_interactions_enabled: true} <-
           EventApp.settings_for_event(context.event.id),
         false <- banned?(context.state, interaction_key) do
      {:ok, context}
    else
      %Setting{} -> {:error, :feature_disabled}
      true -> {:error, :banned}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorized_context(_event, _interaction_key), do: {:error, :invalid_identity}

  defp participant_context(%Event{} = event, interaction_key)
       when is_binary(interaction_key) and byte_size(interaction_key) > 0 do
    with {:ok, context} <- current_context(event),
         false <- banned?(context.state, interaction_key) do
      {:ok, context}
    else
      true -> {:error, :banned}
      {:error, reason} -> {:error, reason}
    end
  end

  defp participant_context(_event, _interaction_key), do: {:error, :invalid_identity}

  defp post_context(event, interaction_key, kind) do
    with {:ok, context} <- participant_context(event, interaction_key) do
      settings = EventApp.settings_for_event(context.event.id)

      enabled =
        case kind do
          "question" -> settings.qa_enabled
          "message" -> settings.chat_enabled and context.state.chat_enabled
        end

      if enabled, do: {:ok, context, settings}, else: {:error, :feature_disabled}
    end
  end

  defp current_context(%Event{} = event) do
    case Events.get_event_with_code(event.code,
           presentation_file: [:presentation_state]
         ) do
      %Event{presentation_file: %{presentation_state: state}} = loaded_event
      when not is_nil(state) ->
        {:ok,
         %{
           event: loaded_event,
           state: state,
           active: Interactions.get_active_interaction(loaded_event, state.position)
         }}

      %Event{} ->
        {:error, :presentation_unavailable}

      nil ->
        {:error, :event_not_found}
    end
  end

  defp public_interaction(nil, _interaction_key), do: nil

  defp public_interaction(%Poll{} = poll, interaction_key) do
    poll = Polls.set_percentages(poll)
    votes = Polls.get_poll_vote(interaction_key, poll.id)

    %{
      kind: :poll,
      id: poll.id,
      title: poll.title,
      multiple: poll.multiple,
      show_results: poll.show_results,
      submitted_option_ids: Enum.map(votes, & &1.poll_opt_id),
      options:
        Enum.map(poll.poll_opts, fn option ->
          %{id: option.id, content: option.content}
          |> maybe_put_result(:vote_count, option.vote_count, poll.show_results)
          |> maybe_put_result(:percentage, option.percentage, poll.show_results)
        end)
    }
  end

  defp public_interaction(%Quiz{} = quiz, interaction_key) do
    quiz = Quizzes.set_percentages(quiz)
    responses = Quizzes.get_quiz_responses(interaction_key, quiz.id)

    %{
      kind: :quiz,
      id: quiz.id,
      title: quiz.title,
      show_results: quiz.show_results,
      submitted_option_ids: Enum.map(responses, & &1.quiz_question_opt_id),
      questions:
        Enum.map(quiz.quiz_questions, fn question ->
          %{
            id: question.id,
            content: question.content,
            options:
              Enum.map(question.quiz_question_opts, fn option ->
                %{id: option.id, content: option.content}
                |> maybe_put_result(:response_count, option.response_count, quiz.show_results)
                |> maybe_put_result(:is_correct, option.is_correct, quiz.show_results)
              end)
          }
        end)
    }
  end

  defp public_interaction(%Form{} = form, interaction_key) do
    submit = Forms.get_form_submit(interaction_key, form.id)

    %{
      kind: :form,
      id: form.id,
      title: form.title,
      submitted: not is_nil(submit),
      response: if(submit, do: submit.response, else: %{}),
      fields: Enum.map(form.fields, &Map.take(&1, [:name, :type, :required]))
    }
  end

  defp public_interaction(%Embed{attendee_visibility: true} = embed, _interaction_key) do
    public_embed(embed)
  end

  defp public_interaction(%Embed{}, _interaction_key), do: nil

  defp public_state(state) do
    %{
      position: state.position,
      chat_enabled: state.chat_enabled,
      chat_visible: state.chat_visible,
      anonymous_chat_enabled: state.anonymous_chat_enabled,
      message_reaction_enabled: state.message_reaction_enabled
    }
  end

  defp latest_result(%{active: active}, _interaction_key) when not is_nil(active), do: nil

  defp latest_result(context, interaction_key) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-30, :minute)

    case Interactions.get_interactions_at_position(context.event, context.state.position) do
      {:ok, interactions} ->
        interactions
        |> Enum.filter(&(match?(%Poll{}, &1) or match?(%Quiz{}, &1)))
        |> Enum.filter(&(NaiveDateTime.compare(&1.updated_at, cutoff) in [:gt, :eq]))
        |> Enum.sort_by(& &1.updated_at, {:desc, NaiveDateTime})
        |> List.first()
        |> public_interaction(interaction_key)

      _ ->
        nil
    end
  end

  defp banned?(state, interaction_key) when is_binary(interaction_key),
    do: interaction_key in (state.banned || [])

  defp banned?(_state, _interaction_key), do: false

  defp public_posts(_context, _interaction_key, _kind, false), do: []

  defp public_posts(context, interaction_key, kind, true) do
    reacted = MapSet.new(Posts.reacted_posts(context.event.id, interaction_key, "👍"))

    context.event.uuid
    |> Posts.list_posts_by_kind(kind, [:reactions])
    |> Enum.filter(&(&1.position == context.state.position))
    |> Enum.map(fn post ->
      %{
        uuid: post.uuid,
        body: post.body,
        name: post.name || "Attendee",
        kind: post.kind,
        pinned: post.pinned,
        like_count: post.like_count,
        love_count: post.love_count,
        lol_count: post.lol_count,
        reacted: MapSet.member?(reacted, post.id),
        inserted_at: post.inserted_at
      }
    end)
  end

  defp public_embed(embed) do
    case safe_embed_url(embed.provider, embed.content) do
      {:inline, url} ->
        %{
          kind: :embed,
          id: embed.id,
          title: embed.title,
          provider: embed.provider,
          inline: true,
          url: url
        }

      {:external, url} ->
        %{
          kind: :embed,
          id: embed.id,
          title: embed.title,
          provider: embed.provider,
          inline: false,
          url: url
        }

      :invalid ->
        nil
    end
  end

  defp safe_embed_url("youtube", content) do
    with %URI{scheme: "https", host: host} = uri <- URI.parse(content),
         true <- host in ["youtube.com", "www.youtube.com", "youtu.be"] do
      video_id =
        if host == "youtu.be",
          do:
            uri.path
            |> to_string()
            |> String.trim_leading("/")
            |> String.split("/")
            |> List.first(),
          else: URI.decode_query(uri.query || "")["v"]

      if present?(video_id),
        do: {:inline, "https://www.youtube.com/embed/#{URI.encode(video_id)}"},
        else: :invalid
    else
      _ -> :invalid
    end
  end

  defp safe_embed_url("vimeo", content) do
    with %URI{scheme: "https", host: host, path: path} <- URI.parse(content),
         true <- host in ["vimeo.com", "www.vimeo.com"],
         video_id when video_id != "" <- path |> to_string() |> String.trim("/") do
      {:inline, "https://player.vimeo.com/video/#{URI.encode(video_id)}"}
    else
      _ -> :invalid
    end
  end

  defp safe_embed_url(provider, content) when provider in ["canva", "googleslides"] do
    allowed_hosts =
      if provider == "canva",
        do: ["canva.com", "www.canva.com"],
        else: ["docs.google.com"]

    case URI.parse(content) do
      %URI{scheme: "https", host: host} ->
        if host in allowed_hosts, do: {:inline, content}, else: :invalid

      _ ->
        :invalid
    end
  end

  defp safe_embed_url("custom", content) do
    with [_, src] <- Regex.run(~r/src=["'](https:\/\/[^"']+)["']/i, content),
         %URI{host: host} <- URI.parse(src) do
      allowlist =
        :claper
        |> Application.get_env(:event_app, [])
        |> Keyword.get(:embed_domain_allowlist, [])

      if host in allowlist, do: {:inline, src}, else: {:external, src}
    else
      _ -> :invalid
    end
  end

  defp safe_embed_url(_provider, _content), do: :invalid

  defp post_name(_attendee, true, %{anonymous_chat_enabled: true}), do: "Anonymous"
  defp post_name(attendee, _anonymous, _state), do: attendee.name || attendee.email || "Attendee"

  defp rate_limit(kind, event_id, interaction_key, limit) do
    case RateLimit.hit("pwa-live:#{kind}:#{event_id}:#{interaction_key}", 60_000, limit) do
      {:allow, _count} -> :ok
      {:deny, _retry_after} -> {:error, :rate_limited}
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp maybe_put_result(map, _key, _value, false), do: map
  defp maybe_put_result(map, key, value, true), do: Map.put(map, key, value)

  defp disabled_summary(event) do
    %{active: false, route: "/app/#{event.code}/live", title: nil, type: nil}
  end

  defp interaction_type(%Poll{}), do: "poll"
  defp interaction_type(%Quiz{}), do: "quiz"
  defp interaction_type(%Form{}), do: "form"
  defp interaction_type(%Embed{}), do: "embed"
end
