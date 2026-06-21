defmodule Claper.EventApp.LiveInteractions do
  @moduledoc """
  Event-scoped adapter between the Claper live engine and the attendee PWA.

  PubSub is treated as an invalidation channel. Every snapshot is rebuilt from
  presentation state and persisted interaction records.
  """

  alias Claper.{Events, Forms, Interactions, Polls, Presentations, Quizzes}
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
         active: public_interaction(context.active, interaction_key)
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
    %{
      kind: :embed,
      id: embed.id,
      title: embed.title,
      provider: embed.provider,
      content: embed.content
    }
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

  defp banned?(state, interaction_key) when is_binary(interaction_key),
    do: interaction_key in (state.banned || [])

  defp banned?(_state, _interaction_key), do: false

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
