defmodule Prode.Integration.GroupsTest do
  @moduledoc """
  Integration tests for group creation, joining, and leaderboard queries.
  """

  use Prode.DataCase, async: true

  import Prode.Factory

  alias Prode.Groups

  test "create group, invite code is 6 uppercase alphanumeric chars" do
    owner = insert(:user)
    tournament = insert(:tournament)

    {:ok, group} = Groups.create_group(owner, %{name: "Mi Grupo", tournament_id: tournament.id})

    assert String.length(group.invite_code) == 6
    assert group.invite_code =~ ~r/^[A-Z0-9]{6}$/
  end

  test "owner is automatically added as admin member" do
    owner = insert(:user)
    tournament = insert(:tournament)

    {:ok, group} = Groups.create_group(owner, %{name: "Mi Grupo", tournament_id: tournament.id})

    [row | _] = Groups.leaderboard_for_group(group.id)
    assert row.total == 0
  end

  test "join by invite code adds user as member" do
    owner = insert(:user)
    joiner = insert(:user)
    tournament = insert(:tournament)

    {:ok, group} = Groups.create_group(owner, %{name: "Grupo", tournament_id: tournament.id})
    assert {:ok, _} = Groups.join_by_invite_code(joiner, group.invite_code)

    assert length(Groups.list_user_groups(joiner)) == 1
  end

  test "joining twice returns :already_member" do
    owner = insert(:user)
    joiner = insert(:user)
    tournament = insert(:tournament)

    {:ok, group} = Groups.create_group(owner, %{name: "Grupo", tournament_id: tournament.id})
    {:ok, _} = Groups.join_by_invite_code(joiner, group.invite_code)

    assert {:error, :already_member} = Groups.join_by_invite_code(joiner, group.invite_code)
  end

  test "joining with invalid code returns :not_found" do
    user = insert(:user)
    assert {:error, :not_found} = Groups.join_by_invite_code(user, "XXXXXX")
  end

  test "leaderboard ranks users by total points descending" do
    tournament = insert(:tournament)
    stage = insert(:stage, tournament: tournament, type: :group, points_multiplier: 1.0)
    owner = insert(:user)
    {:ok, group} = Groups.create_group(owner, %{name: "Grupo", tournament_id: tournament.id})

    user_a = insert(:user)
    user_b = insert(:user)
    {:ok, _} = Groups.join_by_invite_code(user_a, group.invite_code)
    {:ok, _} = Groups.join_by_invite_code(user_b, group.invite_code)

    match = insert(:match, tournament: tournament, stage: stage)

    insert(:prediction,
      user: user_a,
      match: match,
      home_score: 1,
      away_score: 0,
      points_awarded: 5,
      calculated_at: DateTime.utc_now(:second)
    )

    insert(:prediction,
      user: user_b,
      match: match,
      home_score: 2,
      away_score: 0,
      points_awarded: 3,
      calculated_at: DateTime.utc_now(:second)
    )

    rows = Groups.leaderboard_for_group(group.id)
    totals = Enum.map(rows, & &1.total)

    assert totals == Enum.sort(totals, :desc)
    assert 5 in totals
    assert 3 in totals
  end

  test "list_groups_for_users returns only groups the users belong to" do
    t = insert(:tournament)
    u1 = insert(:user)
    u2 = insert(:user)
    u3 = insert(:user)

    {:ok, g1} = Groups.create_group(u1, %{name: "G1", tournament_id: t.id})
    {:ok, g2} = Groups.create_group(u2, %{name: "G2", tournament_id: t.id})
    {:ok, _g3} = Groups.create_group(u3, %{name: "G3", tournament_id: t.id})

    groups = Groups.list_groups_for_users([u1.id, u2.id])
    ids = Enum.map(groups, & &1.id) |> MapSet.new()

    assert MapSet.member?(ids, g1.id)
    assert MapSet.member?(ids, g2.id)
    assert MapSet.size(ids) == 2
  end
end
