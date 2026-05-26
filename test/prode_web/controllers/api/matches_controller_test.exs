defmodule ProdeWeb.Api.MatchesControllerTest do
  use ProdeWeb.ConnCase, async: true

  import Prode.Factory

  alias Prode.Accounts

  defp authed_conn(conn, user) do
    token = Accounts.generate_user_session_token(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/matches (public)" do
    test "returns matches for a tournament", %{conn: conn} do
      tournament = insert(:tournament)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)
      insert(:match, tournament: tournament, home_team: home, away_team: away)

      conn = get(conn, "/api/v1/matches?tournament_id=#{tournament.id}")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
    end

    test "returns error when tournament_id is missing", %{conn: conn} do
      conn = get(conn, "/api/v1/matches")
      body = json_response(conn, 200)
      assert body["error"] =~ "tournament_id"
    end
  end

  describe "GET /api/v1/matches/:id (public)" do
    test "returns a match with teams and stage", %{conn: conn} do
      tournament = insert(:tournament)
      stage = insert(:stage, tournament: tournament)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)
      match = insert(:match, tournament: tournament, home_team: home, away_team: away, stage: stage)

      conn = get(conn, "/api/v1/matches/#{match.id}")
      body = json_response(conn, 200)

      assert body["data"]["id"] == match.id
      assert body["data"]["home_team"]["id"] == home.id
      assert body["data"]["away_team"]["id"] == away.id
      assert body["data"]["stage"]["id"] == stage.id
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, "/api/v1/matches/#{Ecto.UUID.generate()}")
      assert conn.status == 404
    end
  end

  describe "POST /api/v1/matches/:id/predict (authenticated)" do
    test "creates a prediction and returns 200", %{conn: conn} do
      tournament = insert(:tournament)
      stage = insert(:stage, tournament: tournament)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      match =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          stage: stage,
          locked: false
        )

      user = insert(:user)

      conn =
        conn
        |> authed_conn(user)
        |> post("/api/v1/matches/#{match.id}/predict", %{home_score: 2, away_score: 1})

      body = json_response(conn, 200)
      assert body["data"]["home_score"] == 2
      assert body["data"]["away_score"] == 1
    end

    test "returns 401 without token", %{conn: conn} do
      match = insert(:match)
      conn = post(conn, "/api/v1/matches/#{match.id}/predict", %{home_score: 1, away_score: 0})
      assert conn.status == 401
    end
  end
end
