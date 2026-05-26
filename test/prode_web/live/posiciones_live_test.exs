defmodule ProdeWeb.PosicionesLiveTest do
  use ProdeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Prode.Factory

  setup :register_and_log_in_user

  describe "no group state" do
    test "shows no-group message when user has no memberships", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/posiciones")

      assert html =~ "No estás en ningún grupo"
    end
  end

  describe "with a group" do
    setup %{user: user} do
      tournament = insert(:tournament, status: :active)

      group =
        insert(:group,
          tournament: tournament,
          owner: user,
          name: "Los Cracks"
        )

      insert(:membership, group: group, user: user, role: :admin)

      %{group: group, tournament: tournament}
    end

    test "renders leaderboard section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/posiciones")

      assert html =~ "Clasificación"
    end

    test "shows the user in the leaderboard", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/posiciones")

      # User with no display_name shows as "Jugador" and gets the "YO" badge
      assert html =~ "Clasificación"
      assert html =~ "YO"
    end

    test "PubSub broadcast reloads leaderboard without crashing", %{
      conn: conn,
      group: group
    } do
      {:ok, lv, _html} = live(conn, ~p"/posiciones")

      Phoenix.PubSub.broadcast(
        Prode.PubSub,
        "group:#{group.id}",
        {:leaderboard_updated, group.id}
      )

      html = render(lv)
      assert html =~ "Clasificación"
    end
  end
end
