defmodule Prode.Groups do
  @moduledoc """
  Context for group management: creation, invite codes, membership, and leaderboards.
  """

  import Ecto.Query, warn: false

  alias Prode.Accounts.User
  alias Prode.Groups.{Group, Membership}
  alias Prode.Predictions.BonusPrediction
  alias Prode.Repo

  @invite_code_chars ~w(A B C D E F G H J K L M N P Q R S T U V W X Y Z 2 3 4 5 6 7 8 9)
  @max_code_attempts 10

  @doc "Creates a group and automatically makes the owner a member with :admin role."
  def create_group(%User{} = owner, attrs) do
    Repo.transact(fn ->
      code = generate_unique_invite_code()

      group_attrs = Map.merge(attrs, %{owner_id: owner.id, invite_code: code})

      with {:ok, group} <- %Group{} |> Group.changeset(group_attrs) |> Repo.insert() do
        %Membership{}
        |> Membership.changeset(%{
          user_id: owner.id,
          group_id: group.id,
          role: :admin,
          joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert!()

        :telemetry.execute([:prode, :group, :created], %{count: 1}, %{})
        {:ok, group}
      end
    end)
  end

  @doc "Joins a group by its 6-character invite code. Returns {:error, :not_found} or {:error, :already_member}."
  def join_by_invite_code(%User{} = user, code) when is_binary(code) do
    case Repo.get_by(Group, invite_code: String.upcase(code)) do
      nil ->
        {:error, :not_found}

      group ->
        attrs = %{
          user_id: user.id,
          group_id: group.id,
          role: :member,
          joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        case %Membership{} |> Membership.changeset(attrs) |> Repo.insert() do
          {:ok, _membership} -> {:ok, group}
          {:error, changeset} -> check_already_member(changeset)
        end
    end
  end

  @doc "Gets a group by ID. Raises if not found."
  def get_group!(id), do: Repo.get!(Group, id)

  @doc "Returns all groups a user belongs to."
  def list_user_groups(%User{id: user_id}) do
    from(g in Group,
      join: m in Membership,
      on: m.group_id == g.id,
      where: m.user_id == ^user_id,
      order_by: g.name
    )
    |> Repo.all()
  end

  @doc "Returns all groups that any of the given user IDs belong to. Used by PointsCalculator."
  def list_groups_for_users([]), do: []

  def list_groups_for_users(user_ids) when is_list(user_ids) do
    from(g in Group,
      join: m in Membership,
      on: m.group_id == g.id,
      where: m.user_id in ^user_ids,
      distinct: true
    )
    |> Repo.all()
  end

  @doc """
  Returns paginated leaderboard rows for a group.
  Each row: %{id, display_name, avatar_url, total} (total is an integer or nil).
  """
  def leaderboard_for_group(group_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    sql = """
    WITH match_pts AS (
      SELECT p.user_id, COALESCE(SUM(p.points_awarded), 0) AS pts
      FROM predictions p
      JOIN memberships m ON m.user_id = p.user_id AND m.group_id = $1
      GROUP BY p.user_id
    ),
    bonus_pts AS (
      SELECT bp.user_id, COALESCE(SUM(bp.points_awarded), 0) AS pts
      FROM bonus_predictions bp
      JOIN memberships m ON m.user_id = bp.user_id AND m.group_id = $1
      GROUP BY bp.user_id
    )
    SELECT u.id, u.display_name, u.avatar_url,
           COALESCE(mp.pts, 0) + COALESCE(bp.pts, 0) AS total
    FROM users u
    JOIN memberships mem ON mem.user_id = u.id AND mem.group_id = $1
    LEFT JOIN match_pts mp ON mp.user_id = u.id
    LEFT JOIN bonus_pts bp ON bp.user_id = u.id
    ORDER BY total DESC
    LIMIT $2 OFFSET $3
    """

    %{rows: rows, columns: cols} = Repo.query!(sql, [Ecto.UUID.dump!(group_id), limit, offset])

    Enum.map(rows, fn row ->
      cols
      |> Enum.zip(row)
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
    end)
  end

  # --- private ---

  defp generate_unique_invite_code(attempt \\ 0) when attempt < @max_code_attempts do
    code = for(_ <- 1..6, into: "", do: Enum.random(@invite_code_chars))

    if Repo.exists?(from g in Group, where: g.invite_code == ^code) do
      generate_unique_invite_code(attempt + 1)
    else
      code
    end
  end

  defp check_already_member(changeset) do
    already_taken? =
      Enum.any?(changeset.errors, fn
        {:user_id, {"has already been taken", _}} -> true
        _ -> false
      end)

    if already_taken?, do: {:error, :already_member}, else: {:error, changeset}
  end

end
