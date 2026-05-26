defmodule ProdeWeb.Api.GroupsControllerTest do
  use ProdeWeb.ConnCase, async: true

  import Prode.Factory

  alias Prode.Accounts

  defp authed_conn(conn, user) do
    token = Accounts.generate_user_session_token(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/groups (authenticated)" do
    test "returns groups the user belongs to", %{conn: conn} do
      user = insert(:user)
      tournament = insert(:tournament)
      {:ok, group} = Prode.Groups.create_group(user, %{name: "Mi Grupo", tournament_id: tournament.id})

      conn = conn |> authed_conn(user) |> get("/api/v1/groups")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
      assert hd(body["data"])["id"] == group.id
    end

    test "returns 401 without token", %{conn: conn} do
      conn = get(conn, "/api/v1/groups")
      assert conn.status == 401
    end
  end

  describe "POST /api/v1/groups (authenticated)" do
    test "creates a group and returns 201", %{conn: conn} do
      user = insert(:user)
      tournament = insert(:tournament)

      conn =
        conn
        |> authed_conn(user)
        |> post("/api/v1/groups", %{name: "Los Cracks", tournament_id: tournament.id})

      body = json_response(conn, 201)
      assert body["data"]["name"] == "Los Cracks"
      assert String.length(body["data"]["invite_code"]) == 6
    end

    test "returns 422 when name is missing", %{conn: conn} do
      user = insert(:user)
      tournament = insert(:tournament)

      conn =
        conn
        |> authed_conn(user)
        |> post("/api/v1/groups", %{tournament_id: tournament.id})

      assert conn.status == 422
    end
  end

  describe "POST /api/v1/groups/join (authenticated)" do
    test "joins a group by invite code", %{conn: conn} do
      owner = insert(:user)
      joiner = insert(:user)
      tournament = insert(:tournament)
      {:ok, group} = Prode.Groups.create_group(owner, %{name: "El Grupo", tournament_id: tournament.id})

      conn =
        conn
        |> authed_conn(joiner)
        |> post("/api/v1/groups/join", %{invite_code: group.invite_code})

      body = json_response(conn, 200)
      assert body["data"]["id"] == group.id
    end

    test "returns 404 for invalid invite code", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> authed_conn(user)
        |> post("/api/v1/groups/join", %{invite_code: "XXXXXX"})

      assert conn.status == 404
    end

    test "returns 409 when already a member", %{conn: conn} do
      owner = insert(:user)
      tournament = insert(:tournament)
      {:ok, group} = Prode.Groups.create_group(owner, %{name: "El Grupo", tournament_id: tournament.id})

      conn =
        conn
        |> authed_conn(owner)
        |> post("/api/v1/groups/join", %{invite_code: group.invite_code})

      assert conn.status == 409
    end
  end

  describe "GET /api/v1/groups/:id/leaderboard (authenticated)" do
    test "returns leaderboard rows", %{conn: conn} do
      user = insert(:user)
      tournament = insert(:tournament)
      {:ok, group} = Prode.Groups.create_group(user, %{name: "Mi Grupo", tournament_id: tournament.id})

      conn =
        conn
        |> authed_conn(user)
        |> get("/api/v1/groups/#{group.id}/leaderboard")

      body = json_response(conn, 200)
      assert is_list(body["data"])
    end
  end
end
