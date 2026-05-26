defmodule ProdeWeb.PronosticosLiveTest do
  use ProdeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Prode.Factory

  setup :register_and_log_in_user

  defp insert_tournament_with_match(_context) do
    tournament = insert(:tournament, status: :active)
    home = insert(:team, tournament: tournament, code: "ARG")
    away = insert(:team, tournament: tournament, code: "BRA")

    match =
      insert(:match,
        tournament: tournament,
        home_team: home,
        away_team: away,
        round: "Group Stage - 1",
        locked: false,
        status: :scheduled
      )

    %{tournament: tournament, match: match, home: home, away: away}
  end

  describe "mount" do
    test "shows empty state when no tournament exists", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "No hay partidos disponibles"
    end

    test "renders match cards when tournament and matches exist", %{conn: conn} = ctx do
      %{match: match} = insert_tournament_with_match(ctx)

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ match.home_team.code
      assert html =~ match.away_team.code
    end
  end

  describe "prediction sheet" do
    setup :insert_tournament_with_match

    test "opens when clicking an unlocked match", %{conn: conn, match: match} do
      {:ok, lv, _html} = live(conn, ~p"/")

      html = render_click(lv, "open_sheet", %{"match_id" => match.id})

      assert html =~ "Guardar pronóstico"
      assert html =~ match.home_team.code
    end

    test "does not open for a locked match", %{conn: conn} = ctx do
      %{tournament: tournament, home: home, away: away} = ctx

      locked =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          round: "Group Stage - 1",
          locked: true,
          status: :scheduled
        )

      {:ok, lv, _html} = live(conn, ~p"/")

      html = render_click(lv, "open_sheet", %{"match_id" => locked.id})

      refute html =~ "Guardar pronóstico"
    end

    test "dec button is disabled at zero and enabled after increment", %{
      conn: conn,
      match: match
    } do
      {:ok, lv, html} = live(conn, ~p"/")
      render_click(lv, "open_sheet", %{"match_id" => match.id})

      # Both score values start at 0 — dec buttons are disabled
      assert html =~ "disabled"

      # After incrementing, dec button becomes enabled (no longer disabled)
      html = render_click(lv, "inc_home", %{})
      refute html =~ ~s(aria-label="Disminuir #{match.home_team.code}" disabled)
    end

    test "submitting a valid prediction closes the sheet and saves", %{
      conn: conn,
      match: match
    } do
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "open_sheet", %{"match_id" => match.id})
      render_click(lv, "inc_home", %{})
      render_click(lv, "inc_away", %{})
      render_click(lv, "inc_away", %{})

      html = render_click(lv, "submit_prediction", %{})

      refute html =~ "Guardar pronóstico"
      assert html =~ "Pronóstico guardado"
    end
  end

  describe "PubSub" do
    setup :insert_tournament_with_match

    test "updates a match card on :match_updated broadcast", %{conn: conn, match: match} do
      {:ok, lv, html} = live(conn, ~p"/")
      refute html =~ "VIVO"

      Phoenix.PubSub.broadcast(Prode.PubSub, "match:#{match.id}", {
        :match_updated,
        %{match | status: :live, home_score: 1, away_score: 0}
      })

      html = render(lv)
      assert html =~ "VIVO"
    end

    test "locks the sheet when a :match_updated broadcast marks match as locked", %{
      conn: conn,
      match: match
    } do
      {:ok, lv, _html} = live(conn, ~p"/")
      render_click(lv, "open_sheet", %{"match_id" => match.id})

      Phoenix.PubSub.broadcast(Prode.PubSub, "match:#{match.id}", {
        :match_updated,
        %{match | locked: true}
      })

      html = render(lv)
      refute html =~ "Guardar pronóstico"
    end
  end

  describe "round navigation" do
    setup :insert_tournament_with_match

    test "prev button is disabled on first round", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Ronda anterior"
      assert html =~ ~s(disabled)
    end

    test "next round advances to the next round", %{conn: conn} = ctx do
      %{tournament: tournament} = ctx

      now = DateTime.utc_now(:second)
      home2 = insert(:team, tournament: tournament, code: "GER")
      away2 = insert(:team, tournament: tournament, code: "FRA")

      insert(:match,
        tournament: tournament,
        home_team: home2,
        away_team: away2,
        round: "Group Stage - 2",
        locked: false,
        status: :scheduled,
        kickoff_at: DateTime.add(now, 3, :day),
        prediction_lock_at: DateTime.add(now, 2, :day)
      )

      {:ok, lv, html} = live(conn, ~p"/")
      assert html =~ "Fase de Grupos"
      refute html =~ "GER"

      html = render_click(lv, "next_round", %{})
      assert html =~ "GER"
      assert html =~ "FRA"
    end
  end
end
