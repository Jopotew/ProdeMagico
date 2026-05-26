defmodule Prode.GroupsTest do
  use Prode.DataCase, async: true

  import Prode.Factory

  alias Prode.Groups

  describe "create_group/2" do
    test "creates a group and automatically adds owner as admin member" do
      owner = insert(:user)
      tournament = insert(:tournament)

      assert {:ok, group} =
               Groups.create_group(owner, %{
                 name: "Los Pumas",
                 tournament_id: tournament.id,
                 max_members: 20
               })

      assert group.name == "Los Pumas"
      assert group.owner_id == owner.id
      assert String.length(group.invite_code) == 6

      # Owner is automatically a member with admin role
      memberships = Groups.list_user_groups(owner)
      assert length(memberships) == 1
      assert hd(memberships).id == group.id
    end

    test "generates a unique 6-character invite code" do
      owner = insert(:user)
      tournament = insert(:tournament)

      {:ok, g1} = Groups.create_group(owner, %{name: "G1", tournament_id: tournament.id})
      {:ok, g2} = Groups.create_group(owner, %{name: "G2", tournament_id: tournament.id})

      assert g1.invite_code != g2.invite_code
      assert String.length(g1.invite_code) == 6
    end

    test "returns error changeset when name is missing" do
      owner = insert(:user)
      tournament = insert(:tournament)

      assert {:error, changeset} = Groups.create_group(owner, %{tournament_id: tournament.id})
      assert errors_on(changeset).name
    end
  end

  describe "join_by_invite_code/2" do
    test "joins an existing group by invite code" do
      owner = insert(:user)
      joiner = insert(:user)
      tournament = insert(:tournament)

      {:ok, group} = Groups.create_group(owner, %{name: "Mi Grupo", tournament_id: tournament.id})

      assert {:ok, joined_group} = Groups.join_by_invite_code(joiner, group.invite_code)
      assert joined_group.id == group.id

      assert length(Groups.list_user_groups(joiner)) == 1
    end

    test "is case-insensitive" do
      owner = insert(:user)
      joiner = insert(:user)
      tournament = insert(:tournament)

      {:ok, group} = Groups.create_group(owner, %{name: "Mi Grupo", tournament_id: tournament.id})

      assert {:ok, _} = Groups.join_by_invite_code(joiner, String.downcase(group.invite_code))
    end

    test "returns :not_found for a bad invite code" do
      user = insert(:user)
      assert {:error, :not_found} = Groups.join_by_invite_code(user, "XXXXXX")
    end

    test "returns :already_member if user tries to join twice" do
      owner = insert(:user)
      tournament = insert(:tournament)

      {:ok, group} = Groups.create_group(owner, %{name: "Grupo", tournament_id: tournament.id})

      # Owner is already a member after creation
      assert {:error, :already_member} = Groups.join_by_invite_code(owner, group.invite_code)
    end
  end

  describe "list_user_groups/1" do
    test "returns groups the user belongs to, ordered by name" do
      user = insert(:user)
      tournament = insert(:tournament)

      {:ok, _} = Groups.create_group(user, %{name: "Zeta", tournament_id: tournament.id})
      {:ok, _} = Groups.create_group(user, %{name: "Alpha", tournament_id: tournament.id})

      groups = Groups.list_user_groups(user)

      assert length(groups) == 2
      assert Enum.map(groups, & &1.name) == ["Alpha", "Zeta"]
    end

    test "returns empty list for a user with no groups" do
      user = insert(:user)
      assert Groups.list_user_groups(user) == []
    end
  end

  describe "leaderboard_for_group/2" do
    test "returns members ordered by total points descending" do
      tournament = insert(:tournament)
      user1 = insert(:user, display_name: "Ana")
      user2 = insert(:user, display_name: "Bruno")

      group = insert(:group, tournament: tournament, owner: user1)
      insert(:membership, group: group, user: user1, role: :admin)
      insert(:membership, group: group, user: user2)

      # Give user1 some points
      match = insert(:match, tournament: tournament)

      insert(:prediction,
        user: user1,
        match: match,
        home_score: 1,
        away_score: 0,
        points_awarded: 5
      )

      rows = Groups.leaderboard_for_group(group.id)

      assert length(rows) == 2
      [first, second] = rows

      assert first.total == 5
      assert second.total == 0
    end

    test "returns empty list for a group with no members" do
      group = insert(:group)
      assert Groups.leaderboard_for_group(group.id) == []
    end
  end
end
