defmodule Claper.AgendasTest do
  use Claper.DataCase

  alias Claper.Agendas
  alias Claper.Agendas.AgendaItem
  alias Claper.Agendas.AgendaResource
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

    test "create_agenda_item/1 stores a speaker headshot URL and rejects non-http values" do
      event = event_fixture()

      assert {:ok, item} =
               Agendas.create_agenda_item(%{
                 event_id: event.id,
                 starts_at: ~N[2026-06-01 09:00:00],
                 title: "Keynote",
                 speaker_name: "Laura Jones",
                 speaker_image_url: "https://nextgensummit.co/speakers/laura-jones.jpg"
               })

      assert item.speaker_image_url == "https://nextgensummit.co/speakers/laura-jones.jpg"

      assert {:error, changeset} =
               Agendas.create_agenda_item(%{
                 event_id: event.id,
                 starts_at: ~N[2026-06-01 10:00:00],
                 title: "Bad image",
                 speaker_image_url: "javascript:alert(1)"
               })

      assert "must be space-separated http(s) URLs" in errors_on(changeset).speaker_image_url
    end

    test "create_agenda_item/1 accepts a space-separated headshot list for panels" do
      event = event_fixture()

      urls =
        "https://nextgensummit.co/speakers/praveen-varshney.jpg " <>
          "https://nextgensummit.co/speakers/keith-ippel.webp"

      assert {:ok, item} =
               Agendas.create_agenda_item(%{
                 event_id: event.id,
                 starts_at: ~N[2026-06-01 14:00:00],
                 title: "Fireside Chat",
                 speaker_name: "Praveen Varshney + Keith Ippel",
                 speaker_image_url: urls
               })

      assert Claper.Agendas.AgendaItem.image_list(item) == [
               "https://nextgensummit.co/speakers/praveen-varshney.jpg",
               "https://nextgensummit.co/speakers/keith-ippel.webp"
             ]

      assert {:error, changeset} =
               Agendas.create_agenda_item(%{
                 event_id: event.id,
                 starts_at: ~N[2026-06-01 15:00:00],
                 title: "Bad list",
                 speaker_image_url: "https://ok.example/a.jpg notaurl"
               })

      assert "must be space-separated http(s) URLs" in errors_on(changeset).speaker_image_url
    end

    test "create_agenda_item/1 aligns panelists with LinkedIn URLs and rejects other hosts" do
      event = event_fixture()

      assert {:ok, item} =
               Agendas.create_agenda_item(%{
                 event_id: event.id,
                 starts_at: ~N[2026-06-01 14:00:00],
                 title: "Fireside Chat",
                 speaker_name: "Praveen Varshney · Keith Ippel",
                 speaker_image_url:
                   "https://nextgensummit.co/speakers/praveen-varshney.jpg " <>
                     "https://nextgensummit.co/speakers/keith-ippel.webp",
                 speaker_linkedin_url:
                   "https://ca.linkedin.com/in/praveenvarshney " <>
                     "https://ca.linkedin.com/in/keithippel"
               })

      assert Claper.Agendas.AgendaItem.speaker_profiles(item) == [
               %{
                 name: "Praveen Varshney",
                 image_url: "https://nextgensummit.co/speakers/praveen-varshney.jpg",
                 linkedin_url: "https://ca.linkedin.com/in/praveenvarshney"
               },
               %{
                 name: "Keith Ippel",
                 image_url: "https://nextgensummit.co/speakers/keith-ippel.webp",
                 linkedin_url: "https://ca.linkedin.com/in/keithippel"
               }
             ]

      assert {:error, changeset} =
               Agendas.create_agenda_item(%{
                 event_id: event.id,
                 starts_at: ~N[2026-06-01 15:00:00],
                 title: "Bad LinkedIn list",
                 speaker_linkedin_url: "https://example.com/in/not-linkedin"
               })

      assert "must be space-separated LinkedIn http(s) URLs" in errors_on(changeset).speaker_linkedin_url
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

    test "agenda_days/2 and day filtering group by event-local date" do
      event = event_fixture()

      # 08:30 and 17:15 wall time on July 25 in America/Vancouver (PDT, UTC-7)
      morning =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-07-25 15:30:00],
          title: "Opening keynote"
        })

      evening =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-07-26 00:15:00],
          title: "Evening reception"
        })

      # Without a timezone the UTC dates split the event across two days.
      assert [~D[2026-07-25], ~D[2026-07-26]] == Agendas.agenda_days(event.id)

      # In the event timezone both items land on the same local day.
      assert [~D[2026-07-25]] == Agendas.agenda_days(event.id, "America/Vancouver")

      assert [morning.id, evening.id] ==
               event.id
               |> Agendas.list_agenda_items_for_app(
                 day: "2026-07-25",
                 timezone: "America/Vancouver"
               )
               |> Enum.map(& &1.id)
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

  describe "session resources" do
    test "creates, publishes, reorders, and deletes event-scoped HTTPS resources" do
      event = event_fixture()
      agenda_item = agenda_item_fixture(%{event: event})

      assert {:ok, slides} =
               Agendas.create_resource(%{
                 event_id: event.id,
                 agenda_item_id: agenda_item.id,
                 title: "Session slides",
                 kind: "slides",
                 url: "https://cdn.example.com/slides",
                 published: true
               })

      assert {:ok, recording} =
               Agendas.create_resource(%{
                 event_id: event.id,
                 agenda_item_id: agenda_item.id,
                 title: "Recording",
                 kind: "recording",
                 url: "https://video.example.com/session",
                 published: false
               })

      assert Enum.map(Agendas.list_resources(agenda_item.id), & &1.id) == [
               slides.id,
               recording.id
             ]

      assert Enum.map(Agendas.list_resources(agenda_item.id, published_only: true), & &1.id) == [
               slides.id
             ]

      assert {:ok, _resources} = Agendas.move_resource(event.id, recording.id, :up)

      assert Enum.map(Agendas.list_resources(agenda_item.id), & &1.id) == [
               recording.id,
               slides.id
             ]

      assert {:ok, deleted} = Agendas.delete_resource(recording)
      assert deleted.id == recording.id
      refute Repo.get(AgendaResource, recording.id)
    end

    test "rejects non-HTTPS and cross-event resources" do
      event = event_fixture()
      other_event = event_fixture()
      agenda_item = agenda_item_fixture(%{event: event})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Agendas.create_resource(%{
                 event_id: event.id,
                 agenda_item_id: agenda_item.id,
                 title: "Unsafe link",
                 kind: "link",
                 url: "http://example.com"
               })

      assert "must be a valid HTTPS URL" in errors_on(changeset).url

      assert {:error, :agenda_item_not_found} =
               Agendas.create_resource(%{
                 event_id: other_event.id,
                 agenda_item_id: agenda_item.id,
                 title: "Cross event",
                 kind: "pdf",
                 url: "https://example.com/file.pdf"
               })
    end
  end
end
