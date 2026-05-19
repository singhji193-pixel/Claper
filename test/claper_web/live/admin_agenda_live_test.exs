defmodule ClaperWeb.AdminAgendaLiveTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{AccountsFixtures, AgendasFixtures, EventsFixtures}

  alias Claper.Accounts
  alias Claper.Agendas
  alias Claper.Repo

  defp register_and_log_in_admin(%{conn: conn}) do
    {:ok, _role} = Accounts.create_role(%{name: "admin", permissions: %{"all" => true}})
    user = confirmed_user_fixture()
    {:ok, admin} = Accounts.assign_role(user, "admin")

    %{conn: log_in_user(conn, admin), admin: admin}
  end

  describe "admin agenda" do
    setup [:register_and_log_in_admin]

    test "shows agenda in the admin navigation", %{conn: conn} do
      {:ok, _agenda_live, html} = live(conn, ~p"/admin/agenda")

      assert html =~ "Agenda"
      assert html =~ ~p"/admin/agenda"
    end

    test "creates, edits, deletes, and reorders agenda items", %{conn: conn, admin: admin} do
      event = event_fixture(%{user: admin})

      {:ok, new_live, _html} = live(conn, ~p"/admin/agenda/new?event_id=#{event.id}")

      {:ok, _index_live, html} =
        new_live
        |> form("#agenda-item-form",
          agenda_item: %{
            event_id: event.id,
            starts_at: "2026-06-01T09:00",
            title: "Opening keynote",
            description: "Welcome to the event",
            speaker_name: "Avery Singh",
            duration_minutes: "30"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/agenda?event_id=#{event.id}")

      assert html =~ "Opening keynote"
      agenda_item = event.id |> Agendas.list_agenda_items() |> List.first()

      {:ok, edit_live, _html} = live(conn, ~p"/admin/agenda/#{agenda_item}/edit")

      {:ok, _index_live, html} =
        edit_live
        |> form("#agenda-item-form",
          agenda_item: %{
            event_id: event.id,
            starts_at: "2026-06-01T09:30",
            title: "Updated keynote",
            description: "Updated details",
            speaker_name: "Avery Singh",
            duration_minutes: "45",
            position: agenda_item.position
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/agenda?event_id=#{event.id}")

      assert html =~ "Updated keynote"

      first = Repo.reload!(agenda_item)
      second = agenda_item_fixture(%{event: event, title: "Second item"})

      {:ok, index_live, _html} = live(conn, ~p"/admin/agenda?event_id=#{event.id}")

      index_live
      |> element("button[phx-value-id='#{second.id}'][phx-value-direction='up']")
      |> render_click()

      assert [second.id, first.id] == event.id |> Agendas.list_agenda_items() |> Enum.map(& &1.id)

      index_live
      |> element("a[phx-value-id='#{first.id}']")
      |> render_click()

      refute Repo.reload(first)
    end
  end

  describe "admin access control" do
    setup [:register_and_log_in_user]

    test "redirects non-admin users away from admin agenda", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/events"}}} = live(conn, ~p"/admin/agenda")
    end
  end
end
