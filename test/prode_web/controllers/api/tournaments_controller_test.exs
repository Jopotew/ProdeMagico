defmodule ProdeWeb.Api.TournamentsControllerTest do
  use ProdeWeb.ConnCase, async: true

  import Prode.Factory

  describe "GET /api/v1/tournaments" do
    test "returns active tournaments", %{conn: conn} do
      insert(:tournament, status: :active, name: "World Cup", season: 2026)
      insert(:tournament, status: :finished, name: "Old Cup", season: 2022)

      conn = get(conn, "/api/v1/tournaments")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
      assert hd(body["data"])["name"] == "World Cup"
    end

    test "returns empty list when no active tournaments", %{conn: conn} do
      conn = get(conn, "/api/v1/tournaments")
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "GET /api/v1/tournaments/:id" do
    test "returns tournament with stages", %{conn: conn} do
      tournament = insert(:tournament, status: :active)
      insert(:stage, tournament: tournament, name: "Group A")

      conn = get(conn, "/api/v1/tournaments/#{tournament.id}")
      body = json_response(conn, 200)

      assert body["data"]["id"] == tournament.id
      assert length(body["data"]["stages"]) == 1
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, "/api/v1/tournaments/#{Ecto.UUID.generate()}")
      assert conn.status == 404
    end
  end
end
