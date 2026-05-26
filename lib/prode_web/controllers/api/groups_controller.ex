defmodule ProdeWeb.Api.GroupsController do
  use ProdeWeb, :controller

  alias Prode.Groups

  def index(conn, _params) do
    user = conn.assigns.current_user
    groups = Groups.list_user_groups(user)
    json(conn, %{data: Enum.map(groups, &group_json/1)})
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    attrs = %{
      name: params["name"],
      description: params["description"],
      tournament_id: params["tournament_id"],
      max_members: params["max_members"] || 50
    }

    case Groups.create_group(user, attrs) do
      {:ok, group} ->
        conn |> put_status(201) |> json(%{data: group_json(group)})

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: format_errors(changeset)})
    end
  end

  def show(conn, %{"id" => id}) do
    group = Groups.get_group!(id)
    json(conn, %{data: group_json(group)})
  rescue
    Ecto.NoResultsError -> send_resp(conn, 404, ~s({"error":"not found"}))
  end

  def join(conn, %{"invite_code" => code}) do
    user = conn.assigns.current_user

    case Groups.join_by_invite_code(user, code) do
      {:ok, group} ->
        json(conn, %{data: group_json(group)})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "invite code not found"})

      {:error, :already_member} ->
        conn |> put_status(409) |> json(%{error: "already a member of this group"})

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: format_errors(changeset)})
    end
  end

  def join(conn, _params) do
    conn |> put_status(422) |> json(%{error: "invite_code is required"})
  end

  def leaderboard(conn, %{"id" => group_id} = params) do
    limit = String.to_integer(params["limit"] || "50")
    offset = String.to_integer(params["offset"] || "0")

    rows =
      group_id
      |> Groups.leaderboard_for_group(limit: limit, offset: offset)
      |> Enum.map(&normalize_leaderboard_row/1)

    json(conn, %{data: rows})
  rescue
    Ecto.NoResultsError -> send_resp(conn, 404, ~s({"error":"not found"}))
  end

  defp group_json(g) do
    %{
      id: g.id,
      name: g.name,
      description: g.description,
      invite_code: g.invite_code,
      max_members: g.max_members,
      owner_id: g.owner_id,
      tournament_id: g.tournament_id
    }
  end

  defp normalize_leaderboard_row(row) do
    Map.update(row, :id, nil, &normalize_uuid/1)
  end

  defp normalize_uuid(<<_::128>> = bin) do
    case Ecto.UUID.load(bin) do
      {:ok, str} -> str
      _ -> Base.encode16(bin, case: :lower)
    end
  end

  defp normalize_uuid(other), do: other

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
