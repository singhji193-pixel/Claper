defmodule ClaperWeb.EventLiveTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{AgendasFixtures, PresentationsFixtures}

  alias Claper.Agendas
  alias Claper.Repo

  @update_attrs %{name: "some updated name"}

  defp create_event(params) do
    presentation_file = presentation_file_fixture(%{user: params.user}, [:event])
    presentation_state_fixture(%{presentation_file: presentation_file})
    params |> Map.put(:presentation_file, presentation_file)
  end

  describe "Index" do
    setup [:register_and_log_in_user, :create_event]

    test "lists all events", %{conn: conn, presentation_file: presentation_file} do
      {:ok, _index_live, html} = live(conn, ~p"/events")

      assert html =~ "events"
      assert html =~ presentation_file.event.name
    end

    test "shows agenda management link in event actions", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      {:ok, _index_live, html} = live(conn, ~p"/events")

      assert html =~ "Agenda"
      assert html =~ ~p"/e/#{presentation_file.event.code}/manage/agenda"
    end

    test "updates event in listing", %{conn: conn, presentation_file: presentation_file} do
      {:ok, index_live, _html} = live(conn, ~p"/events/#{presentation_file.event.uuid}/edit")

      {:ok, conn} =
        index_live
        |> form("#event-form", event: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, ~p"/events")

      assert html_response(conn, 200) =~ "Updated successfully"
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "deletes event in listing", %{conn: conn, presentation_file: presentation_file} do
      {:ok, index_live, _html} = live(conn, ~p"/events/#{presentation_file.event.uuid}/edit")

      {:ok, conn} =
        index_live
        |> element(~s{a[phx-value-id=#{presentation_file.event.uuid}]})
        |> render_click()
        |> follow_redirect(conn, ~p"/events")

      {:ok, index_live, _html} = live(conn, ~p"/events")

      refute has_element?(index_live, "#event-#{presentation_file.event.uuid}")
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user, :create_event]

    test "displays event", %{conn: conn, presentation_file: presentation_file} do
      {:ok, _show_live, html} =
        live(conn, ~p"/e/#{presentation_file.event.code}")

      assert html =~ "Be the first to react !"
      assert html =~ presentation_file.event.name
    end

    test "shows agenda link in the audience hamburger menu", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      {:ok, _show_live, html} = live(conn, ~p"/e/#{presentation_file.event.code}")

      assert html =~ "Agenda"
      assert html =~ ~p"/e/#{presentation_file.event.code}/agenda"
    end
  end

  describe "Agenda" do
    setup [:register_and_log_in_user, :create_event]

    test "displays agenda items for the event in order", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      second =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 10:00:00],
          title: "Second session"
        })

      first =
        agenda_item_fixture(%{
          event: event,
          starts_at: ~N[2026-06-01 09:00:00],
          title: "First session"
        })

      {:ok, _agenda_live, html} = live(conn, ~p"/e/#{event.code}/agenda")

      assert html =~ event.name
      assert html =~ first.title
      assert html =~ second.title
      assert html =~ "Jun 01, 10:00"
    end

    test "does not expose agenda management controls to audience users", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      agenda_item_fixture(%{event: presentation_file.event})

      {:ok, _agenda_live, html} = live(conn, ~p"/e/#{presentation_file.event.code}/agenda")

      refute html =~ "New agenda item"
      refute html =~ "Edit agenda item"
      refute html =~ "Delete agenda item"
      refute html =~ "phx-click=\"delete\""
    end
  end

  describe "Owner agenda management" do
    setup [:register_and_log_in_user, :create_event]

    test "creates, edits, deletes, and reorders agenda items from the event owner flow", %{
      conn: conn,
      presentation_file: presentation_file
    } do
      event = presentation_file.event

      {:ok, new_live, _html} = live(conn, ~p"/e/#{event.code}/manage/agenda/new")

      {:ok, _index_live, html} =
        new_live
        |> form("#agenda-item-form",
          agenda_item: %{
            starts_at: "2026-06-01T09:00",
            title: "Opening keynote",
            description: "Welcome to the event",
            speaker_name: "Avery Singh",
            duration_minutes: "30"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/e/#{event.code}/manage/agenda")

      assert html =~ "Opening keynote"
      agenda_item = event.id |> Agendas.list_agenda_items() |> List.first()

      {:ok, edit_live, _html} =
        live(conn, ~p"/e/#{event.code}/manage/agenda/#{agenda_item}/edit")

      {:ok, _index_live, html} =
        edit_live
        |> form("#agenda-item-form",
          agenda_item: %{
            starts_at: "2026-06-01T09:30",
            title: "Updated keynote",
            description: "Updated details",
            speaker_name: "Avery Singh",
            duration_minutes: "45",
            position: agenda_item.position
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/e/#{event.code}/manage/agenda")

      assert html =~ "Updated keynote"

      first = Repo.reload!(agenda_item)
      second = agenda_item_fixture(%{event: event, title: "Second item"})

      {:ok, index_live, _html} = live(conn, ~p"/e/#{event.code}/manage/agenda")

      index_live
      |> element("button[phx-value-id='#{second.id}'][phx-value-direction='up']")
      |> render_click()

      assert [second.id, first.id] == event.id |> Agendas.list_agenda_items() |> Enum.map(& &1.id)

      index_live
      |> element("button[phx-value-id='#{first.id}'][phx-click='delete']")
      |> render_click()

      refute Repo.reload(first)
    end

    test "redirects non-owners away from agenda management", %{conn: conn} do
      other_user = Claper.AccountsFixtures.confirmed_user_fixture()
      presentation_file = presentation_file_fixture(%{user: other_user}, [:event])
      presentation_state_fixture(%{presentation_file: presentation_file})

      assert {:error, {:redirect, %{to: "/events"}}} =
               live(conn, ~p"/e/#{presentation_file.event.code}/manage/agenda")
    end
  end
end
