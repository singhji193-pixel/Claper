defmodule Claper.EventApp.LiveInteractionsTest do
  use Claper.DataCase

  import Claper.{PollsFixtures, PresentationsFixtures}

  alias Claper.EventApp
  alias Claper.EventApp.LiveInteractions

  setup do
    presentation_file = presentation_file_fixture(%{}, [:event])
    presentation_state_fixture(%{presentation_file: presentation_file, position: 0})

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
      settings: settings,
      interaction_key: Ecto.UUID.generate()
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
end
