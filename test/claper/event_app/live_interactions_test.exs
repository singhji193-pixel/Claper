defmodule Claper.EventApp.LiveInteractionsTest do
  use Claper.DataCase

  import Claper.{PollsFixtures, PresentationsFixtures}

  alias Claper.{Embeds, EventApp, Presentations, Repo}
  alias Claper.EventApp.Attendee
  alias Claper.EventApp.LiveInteractions

  setup do
    presentation_file = presentation_file_fixture(%{}, [:event])

    state =
      presentation_state_fixture(%{
        presentation_file: presentation_file,
        position: 0,
        chat_enabled: true,
        anonymous_chat_enabled: false
      })

    interaction_key = Ecto.UUID.generate()

    %Attendee{interaction_key: interaction_key}
    |> Attendee.changeset(%{
      event_id: presentation_file.event_id,
      email: "avery@example.com",
      name: "Avery Singh",
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()

    poll =
      poll_fixture(%{
        presentation_file_id: presentation_file.id,
        position: 0,
        enabled: true,
        show_results: false,
        title: "Which topic should we explore?"
      })

    settings = EventApp.get_or_create_settings(presentation_file.event_id)

    {:ok, settings} =
      EventApp.update_settings(settings, %{
        live_interactions_enabled: true,
        qa_enabled: true,
        chat_enabled: true
      })

    %{
      event: presentation_file.event,
      poll: poll,
      state: state,
      settings: settings,
      interaction_key: interaction_key,
      presentation_file: presentation_file
    }
  end

  test "returns an authoritative active interaction snapshot", context do
    assert {:ok, snapshot} =
             LiveInteractions.snapshot(context.event, context.interaction_key)

    assert snapshot.enabled
    assert snapshot.state.position == 0
    assert snapshot.active.kind == :poll
    assert snapshot.active.id == context.poll.id
    assert snapshot.active.title == "Which topic should we explore?"
    refute Map.has_key?(List.first(snapshot.active.options), :vote_count)
  end

  test "shapes an anonymous pre-auth snapshot without querying a nil identity", context do
    assert {:ok, snapshot} = LiveInteractions.snapshot(context.event, nil)

    assert snapshot.active.kind == :poll
    assert snapshot.active.submitted_option_ids == []
    assert snapshot.questions == []
    assert snapshot.messages == []
  end

  test "submits a scoped poll vote and restores it on refresh", context do
    option = List.first(context.poll.poll_opts)

    assert {:ok, snapshot} =
             LiveInteractions.vote_poll(
               context.event,
               context.interaction_key,
               context.poll.id,
               [option.id]
             )

    assert snapshot.active.submitted_option_ids == [option.id]

    assert {:ok, refreshed} =
             LiveInteractions.snapshot(context.event, context.interaction_key)

    assert refreshed.active.submitted_option_ids == [option.id]
  end

  test "refuses submissions when Live is disabled", context do
    assert {:ok, _settings} =
             EventApp.update_settings(context.settings, %{live_interactions_enabled: false})

    assert {:error, :feature_disabled} =
             LiveInteractions.vote_poll(
               context.event,
               context.interaction_key,
               context.poll.id,
               [List.first(context.poll.poll_opts).id]
             )
  end

  test "exposes only a safe summary for bootstrap", context do
    summary = LiveInteractions.summary(context.event, context.settings)

    assert summary == %{
             active: true,
             route: "/app/#{context.event.code}/live",
             title: context.poll.title,
             type: "poll"
           }
  end

  test "keeps the latest closed Poll result for the current slide", context do
    assert {:ok, _poll} = Claper.Polls.set_disabled(context.poll.id)

    assert {:ok, snapshot} =
             LiveInteractions.snapshot(context.event, context.interaction_key)

    assert is_nil(snapshot.active)
    assert snapshot.latest_result.kind == :poll
    assert snapshot.latest_result.id == context.poll.id
  end

  test "creates named Q&A and Chat posts and toggles question votes", context do
    assert {:ok, question, _settings} =
             LiveInteractions.create_post(
               context.event,
               context.interaction_key,
               "question",
               "How will this affect founders?",
               true
             )

    assert question.kind == "question"
    assert question.name == "Avery Singh"

    assert {:ok, :added, reacted} =
             LiveInteractions.toggle_reaction(
               context.event,
               context.interaction_key,
               question.uuid,
               "👍"
             )

    assert reacted.like_count == 1

    assert {:ok, :removed, unreacted} =
             LiveInteractions.toggle_reaction(
               context.event,
               context.interaction_key,
               question.uuid,
               "👍"
             )

    assert unreacted.like_count == 0

    assert {:ok, snapshot} =
             LiveInteractions.snapshot(context.event, context.interaction_key)

    assert [%{body: "How will this affect founders?", kind: "question"}] = snapshot.questions
    assert snapshot.messages == []
  end

  test "uses Anonymous only when presenter policy permits it", context do
    assert {:ok, _state} =
             Presentations.update_presentation_state(context.state, %{
               anonymous_chat_enabled: true
             })

    assert {:ok, post, _settings} =
             LiveInteractions.create_post(
               context.event,
               context.interaction_key,
               "message",
               "Hello everyone",
               true
             )

    assert post.name == "Anonymous"
    assert post.attendee_identifier == context.interaction_key
  end

  test "rate limits attendee posts", context do
    for index <- 1..5 do
      assert {:ok, _post, _settings} =
               LiveInteractions.create_post(
                 context.event,
                 context.interaction_key,
                 "message",
                 "Message #{index}",
                 false
               )
    end

    assert {:error, :rate_limited} =
             LiveInteractions.create_post(
               context.event,
               context.interaction_key,
               "message",
               "Message 6",
               false
             )
  end

  test "shapes standard attendee embeds without returning raw HTML", context do
    assert {:ok, _poll} = Claper.Polls.set_disabled(context.poll.id)

    assert {:ok, embed} =
             Embeds.create_embed(%{
               title: "Watch the session",
               content: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
               provider: "youtube",
               enabled: true,
               attendee_visibility: true,
               position: 0,
               presentation_file_id: context.presentation_file.id
             })

    assert {:ok, snapshot} =
             LiveInteractions.snapshot(context.event, context.interaction_key)

    assert snapshot.active.kind == :embed
    assert snapshot.active.inline
    assert snapshot.active.url == "https://www.youtube.com/embed/dQw4w9WgXcQ"
    refute Map.has_key?(snapshot.active, :content)

    assert {:ok, _embed} = Embeds.set_disabled(embed.id)

    assert {:ok, _custom_embed} =
             Embeds.create_embed(%{
               title: "Partner content",
               content: ~s(<iframe src="https://partner.example.com/session"></iframe>),
               provider: "custom",
               enabled: true,
               attendee_visibility: true,
               position: 0,
               presentation_file_id: context.presentation_file.id
             })

    assert {:ok, custom_snapshot} =
             LiveInteractions.snapshot(context.event, context.interaction_key)

    assert custom_snapshot.active.kind == :embed
    refute custom_snapshot.active.inline
    assert custom_snapshot.active.url == "https://partner.example.com/session"
    refute Map.has_key?(custom_snapshot.active, :content)
  end
end
