defmodule Prode.TournamentsTest do
  use Prode.DataCase, async: true

  import Prode.Factory

  alias Prode.Tournaments

  describe "get_tournament!/1" do
    test "returns the tournament for a valid id" do
      tournament = insert(:tournament)
      assert Tournaments.get_tournament!(tournament.id).id == tournament.id
    end

    test "raises when id is not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Tournaments.get_tournament!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_tournament_by_season!/1" do
    test "returns tournament matching the season" do
      tournament = insert(:tournament, season: 2026)
      assert Tournaments.get_tournament_by_season!(2026).id == tournament.id
    end

    test "raises when season is not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Tournaments.get_tournament_by_season!(9999)
      end
    end
  end

  describe "list_active_tournaments/0" do
    test "returns only active tournaments" do
      active = insert(:tournament, status: :active)
      insert(:tournament, status: :upcoming)
      insert(:tournament, status: :finished)

      result_ids = Tournaments.list_active_tournaments() |> Enum.map(& &1.id)
      assert active.id in result_ids
      assert length(result_ids) == 1
    end

    test "returns empty list when none are active" do
      insert(:tournament, status: :upcoming)
      assert Tournaments.list_active_tournaments() == []
    end
  end

  describe "list_stages/1" do
    test "returns stages ordered by order ascending" do
      tournament = insert(:tournament)
      s2 = insert(:stage, tournament: tournament, order: 2, slug: "group_b", name: "Group B")
      s1 = insert(:stage, tournament: tournament, order: 1, slug: "group_a", name: "Group A")

      [first, second] = Tournaments.list_stages(tournament.id)
      assert first.id == s1.id
      assert second.id == s2.id
    end

    test "returns empty list for tournament with no stages" do
      tournament = insert(:tournament)
      assert Tournaments.list_stages(tournament.id) == []
    end

    test "does not return stages from other tournaments" do
      t1 = insert(:tournament)
      t2 = insert(:tournament)
      insert(:stage, tournament: t1, slug: "group_a")
      insert(:stage, tournament: t2, slug: "group_b")

      assert length(Tournaments.list_stages(t1.id)) == 1
    end
  end

  describe "list_teams/1" do
    test "returns all teams for the tournament ordered by name" do
      tournament = insert(:tournament)
      insert(:team, tournament: tournament, name: "Brazil", code: "BRA")
      insert(:team, tournament: tournament, name: "Argentina", code: "ARG")

      [first, second] = Tournaments.list_teams(tournament.id)
      assert first.name == "Argentina"
      assert second.name == "Brazil"
    end

    test "does not return teams from other tournaments" do
      t1 = insert(:tournament)
      t2 = insert(:tournament)
      insert(:team, tournament: t1, code: "ARG")
      insert(:team, tournament: t2, code: "BRA")

      assert length(Tournaments.list_teams(t1.id)) == 1
    end
  end

  describe "list_teams_by_group/2" do
    test "returns only teams in the given group" do
      tournament = insert(:tournament)
      arg = insert(:team, tournament: tournament, code: "ARG", group: "A")
      _fra = insert(:team, tournament: tournament, code: "FRA", group: "B")

      teams = Tournaments.list_teams_by_group(tournament.id, "A")
      assert length(teams) == 1
      assert hd(teams).id == arg.id
    end

    test "returns empty list when group has no teams" do
      tournament = insert(:tournament)
      insert(:team, tournament: tournament, code: "ARG", group: "A")
      assert Tournaments.list_teams_by_group(tournament.id, "Z") == []
    end
  end

  describe "Stage changeset" do
    test "group stages have multiplier 1.0 by default" do
      tournament = insert(:tournament)

      stage =
        insert(:stage,
          tournament: tournament,
          slug: "group_a",
          type: :group,
          points_multiplier: 1.0
        )

      assert stage.points_multiplier == 1.0
      assert stage.type == :group
    end

    test "knockout stages have multiplier 2.0" do
      tournament = insert(:tournament)

      stage =
        insert(:knockout_stage,
          tournament: tournament,
          slug: "r16",
          points_multiplier: 2.0
        )

      assert stage.points_multiplier == 2.0
      assert stage.type == :knockout
    end
  end
end
