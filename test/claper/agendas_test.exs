defmodule Claper.AgendasTest do
  use Claper.DataCase

  alias Claper.Agendas
  alias Claper.Agendas.AgendaItem
  alias Claper.Repo

  import Claper.{AgendasFixtures, EventsFixtures}

  describe "agenda items" do
    test "create_agenda_item/1 creates an agenda item at the end of an event agenda" do
      event = event_fixture()

      assert {:ok, first} =
               Agendas.create_agenda_item(%{
                 event_id: event.id,
                 starts_at: ~N[2026-06-01 09:00:00],
                 title: "Welcome"
               })

      assert {:ok, second} =
               Agendas.create_agenda_item(%{
                 event_id: event.id,
                 starts_at: ~N[2026-06-01 10:00:00],
                 title: "Keynote"
               })

      assert first.position == 0
      assert second.position == 1
    end

    test "create_agenda_item/1 rejects invalid attributes" do
      assert {:error, changeset} =
               Agendas.create_agenda_item(%{
                 title: "",
                 duration_minutes: -5
               })

      assert "can't be blank" in errors_on(changeset).event_id
      assert "can't be blank" in errors_on(changeset).starts_at
      assert "can't be blank" in errors_on(changeset).title
      assert "must be greater than 0" in errors_on(changeset).duration_minutes
    end

    test "list_agenda_items/1 only returns items for the requested event in agenda order" do
      event = event_fixture()
      other_event = event_fixture()

      late =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 11:00:00],
          title: "Late"
        })

      early =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 09:00:00],
          title: "Early"
        })

      _other = agenda_item_fixture(%{event: other_event, title: "Other"})

      assert [late.id, early.id] == Enum.map(Agendas.list_agenda_items(event.id), & &1.id)
    end

    test "get_agenda_item_for_event!/2 scopes lookup to the event" do
      event = event_fixture()
      other_event = event_fixture()
      agenda_item = agenda_item_fixture(%{event: event})

      assert Agendas.get_agenda_item_for_event!(event.id, agenda_item.id).id == agenda_item.id

      assert_raise Ecto.NoResultsError, fn ->
        Agendas.get_agenda_item_for_event!(other_event.id, agenda_item.id)
      end
    end

    test "update_agenda_item/2 updates agenda content" do
      agenda_item = agenda_item_fixture()

      assert {:ok, updated} =
               Agendas.update_agenda_item(agenda_item, %{
                 title: "Updated title",
                 speaker_name: "Updated speaker",
                 speaker_title: "Founder",
                 speaker_company: "CoreOrbit",
                 location_name: "Main Stage",
                 track_name: "Growth",
                 session_type: "Keynote",
                 duration_minutes: 45
               })

      assert updated.title == "Updated title"
      assert updated.speaker_name == "Updated speaker"
      assert updated.speaker_title == "Founder"
      assert updated.speaker_company == "CoreOrbit"
      assert updated.location_name == "Main Stage"
      assert updated.track_name == "Growth"
      assert updated.session_type == "Keynote"
      assert updated.duration_minutes == 45
    end

    test "list_agenda_items_for_app/2 filters by day and track" do
      event = event_fixture()

      growth =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 09:00:00],
          title: "Growth playbook",
          track_name: "Growth"
        })

      product =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 10:00:00],
          title: "Product clinic",
          track_name: "Product"
        })

      next_day =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-02 09:00:00],
          title: "Founder breakfast",
          track_name: "Growth"
        })

      assert [growth.id, product.id] ==
               event.id
               |> Agendas.list_agenda_items_for_app(day: "2026-06-01")
               |> Enum.map(& &1.id)

      assert [growth.id] ==
               event.id
               |> Agendas.list_agenda_items_for_app(day: "2026-06-01", track: "Growth")
               |> Enum.map(& &1.id)

      assert [~D[2026-06-01], ~D[2026-06-02]] == Agendas.agenda_days(event.id)
      assert ["Growth", "Product"] == Agendas.agenda_tracks(event.id)
      assert next_day.id
    end

    test "delete_agenda_item/1 removes item and normalizes positions" do
      event = event_fixture()
      first = agenda_item_fixture(%{event: event, title: "First"})
      second = agenda_item_fixture(%{event: event, title: "Second"})
      third = agenda_item_fixture(%{event: event, title: "Third"})

      assert {:ok, deleted} = Agendas.delete_agenda_item(second)
      assert deleted.id == second.id

      assert [{first.id, 0}, {third.id, 1}] ==
               event.id
               |> Agendas.list_agenda_items()
               |> Enum.map(&{&1.id, &1.position})
    end

    test "move_agenda_item/3 reorders within one event" do
      event = event_fixture()
      first = agenda_item_fixture(%{event: event, title: "First"})
      second = agenda_item_fixture(%{event: event, title: "Second"})
      third = agenda_item_fixture(%{event: event, title: "Third"})

      assert {:ok, _items} = Agendas.move_agenda_item(event.id, third.id, :up)

      assert [first.id, third.id, second.id] ==
               event.id
               |> Agendas.list_agenda_items()
               |> Enum.map(& &1.id)

      assert {:ok, _items} = Agendas.move_agenda_item(event.id, first.id, :down)

      assert [third.id, first.id, second.id] ==
               event.id
               |> Agendas.list_agenda_items()
               |> Enum.map(& &1.id)
    end

    test "event deletion cascades agenda items" do
      event = event_fixture()
      agenda_item = agenda_item_fixture(%{event: event})

      assert {:ok, _event} = Claper.Events.delete_event(event)
      refute Repo.get(AgendaItem, agenda_item.id)
    end
  end
end
