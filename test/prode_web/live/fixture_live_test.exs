defmodule ProdeWeb.FixtureLiveTest do
  use ProdeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Prode.Factory

  setup :register_and_log_in_user

  describe "empty state" do
    test "shows no-fixture message when no tournament exists", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/fixture")
      assert html =~ "No hay fixture disponible"
    end
  end

  describe "with matches" do
    setup do
      tournament = insert(:tournament, status: :active)
      home = insert(:team, tournament: tournament, code: "ARG")
      away = insert(:team, tournament: tournament, code: "BRA")

      match =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          round: "Group Stage - 1",
          kickoff_at: ~U[2026-06-14 18:00:00Z]
        )

      %{tournament: tournament, match: match}
    end

    test "renders day headings for each match day", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/fixture")
      assert html =~ "fixture-day-"
    end

    test "renders team codes in fixture rows", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/fixture")
      assert html =~ "ARG"
      assert html =~ "BRA"
    end

    test "PubSub broadcast updates match score", %{conn: conn, match: match} do
      {:ok, lv, _html} = live(conn, ~p"/fixture")

      Phoenix.PubSub.broadcast(Prode.PubSub, "match:#{match.id}", {
        :match_updated,
        %{match | status: :finished, home_score: 2, away_score: 1}
      })

      html = render(lv)
      assert html =~ "2"
      assert html =~ "1"
    end
  end
end
