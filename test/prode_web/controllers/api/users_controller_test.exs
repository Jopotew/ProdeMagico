defmodule ProdeWeb.Api.UsersControllerTest do
  use ProdeWeb.ConnCase, async: true

  import Prode.Factory

  alias Prode.Accounts

  defp authed_conn(conn, user) do
    token = Accounts.generate_user_session_token(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/users/me (authenticated)" do
    test "returns current user data", %{conn: conn} do
      user = insert(:user, display_name: "Ana", email: "ana@example.com")

      conn = conn |> authed_conn(user) |> get("/api/v1/users/me")
      body = json_response(conn, 200)

      assert body["data"]["id"] == user.id
      assert body["data"]["email"] == "ana@example.com"
      assert body["data"]["display_name"] == "Ana"
    end

    test "returns 401 without token", %{conn: conn} do
      conn = get(conn, "/api/v1/users/me")
      assert conn.status == 401
    end
  end

  describe "GET /api/v1/users/me/predictions (authenticated)" do
    test "returns user predictions", %{conn: conn} do
      user = insert(:user)
      match = insert(:match)
      insert(:prediction, user: user, match: match, home_score: 1, away_score: 0)

      conn = conn |> authed_conn(user) |> get("/api/v1/users/me/predictions")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
      assert hd(body["data"])["home_score"] == 1
    end

    test "returns empty list when user has no predictions", %{conn: conn} do
      user = insert(:user)

      conn = conn |> authed_conn(user) |> get("/api/v1/users/me/predictions")
      assert json_response(conn, 200)["data"] == []
    end
  end
end
