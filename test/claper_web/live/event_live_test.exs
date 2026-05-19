defmodule ClaperWeb.EventLiveTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{AgendasFixtures, PresentationsFixtures}

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
end
