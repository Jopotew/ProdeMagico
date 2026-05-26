defmodule ProdeWeb.BonusLiveTest do
  use ProdeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Prode.Factory

  setup :register_and_log_in_user

  defp setup_tournament_with_teams(_ctx) do
    tournament = insert(:tournament, status: :active, bonus_predictions_lock_at: nil)
    _team_a1 = insert(:team, tournament: tournament, code: "ARG", name: "Argentina", group: "A")
    _team_a2 = insert(:team, tournament: tournament, code: "BRA", name: "Brasil", group: "A")
    %{tournament: tournament}
  end

  describe "group winner pickers" do
    setup :setup_tournament_with_teams

    test "renders group winner dropdowns", %{conn: conn, tournament: t} do
      {:ok, _lv, html} = live(conn, ~p"/torneos/#{t.id}/bonus")
      assert html =~ "Campeón de grupo"
      assert html =~ "group-winner-A"
    end

    test "shows team options in group A dropdown", %{conn: conn, tournament: t} do
      {:ok, _lv, html} = live(conn, ~p"/torneos/#{t.id}/bonus")
      assert html =~ "ARG"
      assert html =~ "BRA"
    end

    test "saving a group winner updates the bonus_map", %{
      conn: conn,
      tournament: t
    } do
      team = insert(:team, tournament: t, code: "URU", name: "Uruguay", group: "B",
                    api_football_id: 99_901)

      {:ok, lv, _html} = live(conn, ~p"/torneos/#{t.id}/bonus")

      html =
        render_change(lv, "pick_group_winner", %{
          "group" => "B",
          "value" => to_string(team.api_football_id)
        })

      assert html =~ "hero-check-circle"
    end

    test "empty selection leaves the bonus_map unchanged", %{conn: conn, tournament: t} do
      {:ok, lv, _html} = live(conn, ~p"/torneos/#{t.id}/bonus")
      render_change(lv, "pick_group_winner", %{"group" => "A", "value" => ""})
      html = render(lv)
      refute html =~ "hero-check-circle"
    end
  end

  describe "top scorer picker" do
    setup :setup_tournament_with_teams

    test "renders top scorer section", %{conn: conn, tournament: t} do
      {:ok, _lv, html} = live(conn, ~p"/torneos/#{t.id}/bonus")
      assert html =~ "Goleador del torneo"
      assert html =~ "top-scorer-input"
    end

    test "saving a player name shows the checkmark", %{conn: conn, tournament: t} do
      {:ok, lv, _html} = live(conn, ~p"/torneos/#{t.id}/bonus")

      html = render_submit(lv, "save_top_scorer", %{"player_name" => "Lionel Messi"})

      assert html =~ "hero-check-circle"
    end

    test "empty player name does not show checkmark", %{conn: conn, tournament: t} do
      {:ok, lv, _html} = live(conn, ~p"/torneos/#{t.id}/bonus")
      render_submit(lv, "save_top_scorer", %{"player_name" => ""})
      html = render(lv)
      refute html =~ "hero-check-circle"
    end
  end

  describe "locked state" do
    test "shows locked banner and read-only values when bonus_predictions_lock_at is in the past",
         %{conn: conn} do
      past = DateTime.add(DateTime.utc_now(), -1, :hour)
      tournament = insert(:tournament, status: :active, bonus_predictions_lock_at: past)

      {:ok, _lv, html} = live(conn, ~p"/torneos/#{tournament.id}/bonus")
      assert html =~ "bloquearon"
      refute html =~ "group-winner-A"
    end
  end
end
