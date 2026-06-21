defmodule ClaperWeb.PwaControllerTest do
  use ClaperWeb.ConnCase

  import Claper.{AgendasFixtures, EventsFixtures}

  describe "GET /api/pwa/:code/bootstrap" do
    test "returns event app bootstrap data", %{conn: conn} do
      event = event_fixture()
      agenda_item_fixture(%{event: event})

      conn = get(conn, ~p"/api/pwa/#{event.code}/bootstrap")

      assert %{
               "event" => %{"code" => code, "name" => name},
               "features" => %{"agenda" => %{"count" => 1}},
               "settings" => %{"enabled" => true},
               "attendee" => %{"identifier_present" => false, "authenticated" => false}
             } = json_response(conn, 200)

      assert code == event.code
      assert name == event.name
    end

    test "returns not found for missing events", %{conn: conn} do
      conn = get(conn, ~p"/api/pwa/missing/bootstrap")

      assert %{"error" => "event_not_found"} = json_response(conn, 404)
    end
  end

  describe "PWA static assets" do
    test "serves the manifest and service worker", %{conn: conn} do
      conn = get(conn, "/manifest.webmanifest")

      assert response(conn, 200) =~ "NextGen Summit"

      conn = build_conn() |> get("/sw.js")

      assert response(conn, 200) =~ "nextgen-summit-liveview-v3-auth"
    end
  end
end
