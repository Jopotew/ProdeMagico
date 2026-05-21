defmodule Prode.External.ApiFootballTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Prode.External.ApiFootball

  @fixtures_dir "test/support/fixtures/api_football"

  setup do
    bypass = Bypass.open()
    original = Application.get_env(:prode, :api_football_base_url)
    Application.put_env(:prode, :api_football_base_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      if original do
        Application.put_env(:prode, :api_football_base_url, original)
      else
        Application.delete_env(:prode, :api_football_base_url)
      end
    end)

    {:ok, bypass: bypass}
  end

  test "get_status/0 returns parsed status map", %{bypass: bypass} do
    body = File.read!(Path.join(@fixtures_dir, "status.json"))

    Bypass.expect_once(bypass, "GET", "/status", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.put_resp_header("x-ratelimit-requests-remaining", "95")
      |> Plug.Conn.send_resp(200, body)
    end)

    assert {:ok, status} = ApiFootball.get_status()
    assert status["requests"]["current"] == 5
    assert status["requests"]["limit_day"] == 100
    assert status["subscription"]["plan"] == "Free"
  end

  test "list_fixtures/1 returns a list of fixtures", %{bypass: bypass} do
    body = File.read!(Path.join(@fixtures_dir, "fixtures_list.json"))

    Bypass.expect_once(bypass, "GET", "/fixtures", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, body)
    end)

    assert {:ok, fixtures} = ApiFootball.list_fixtures(league: 1, season: 2026)
    assert length(fixtures) == 2
    assert hd(fixtures)["fixture"]["id"] == 1_149_393
    assert hd(fixtures)["teams"]["home"]["name"] == "Mexico"
  end

  test "get_fixture/1 returns a single fixture map", %{bypass: bypass} do
    body = File.read!(Path.join(@fixtures_dir, "fixture_single.json"))

    Bypass.expect_once(bypass, "GET", "/fixtures", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, body)
    end)

    assert {:ok, fixture} = ApiFootball.get_fixture(1_149_393)
    assert fixture["fixture"]["id"] == 1_149_393
  end

  test "get_fixture/1 returns not_found when response is empty", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/fixtures", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, ~s({"get":"fixtures","response":[]}))
    end)

    assert {:error, :not_found} = ApiFootball.get_fixture(999_999)
  end

  test "list_top_scorers/1 returns scorer list", %{bypass: bypass} do
    body = File.read!(Path.join(@fixtures_dir, "top_scorers.json"))

    Bypass.expect_once(bypass, "GET", "/players/topscorers", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, body)
    end)

    assert {:ok, scorers} = ApiFootball.list_top_scorers(league: 1, season: 2026)
    assert length(scorers) == 1
    assert hd(scorers)["player"]["name"] == "K. Mbappe"
    assert hd(scorers)["statistics"] |> hd() |> get_in(["goals", "total"]) == 8
  end

  test "returns http_error tuple on non-200 response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/fixtures", fn conn ->
      Plug.Conn.send_resp(conn, 429, "Too Many Requests")
    end)

    assert {:error, {:http_error, 429}} = ApiFootball.list_fixtures(league: 1, season: 2026)
  end
end
