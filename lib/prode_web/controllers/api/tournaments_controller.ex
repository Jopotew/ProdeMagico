defmodule ProdeWeb.Api.TournamentsController do
  use ProdeWeb, :controller

  alias Prode.Tournaments

  def index(conn, _params) do
    tournaments = Tournaments.list_active_tournaments()
    json(conn, %{data: Enum.map(tournaments, &tournament_json/1)})
  end

  def show(conn, %{"id" => id}) do
    tournament = Tournaments.get_tournament!(id)
    stages = Tournaments.list_stages(tournament.id)
    json(conn, %{data: tournament_json(tournament) |> Map.put(:stages, Enum.map(stages, &stage_json/1))})
  rescue
    Ecto.NoResultsError -> send_resp(conn, 404, ~s({"error":"not found"}))
  end

  defp tournament_json(t) do
    %{
      id: t.id,
      name: t.name,
      season: t.season,
      status: t.status,
      starts_on: t.starts_on,
      ends_on: t.ends_on,
      bonus_predictions_lock_at: t.bonus_predictions_lock_at
    }
  end

  defp stage_json(s) do
    %{id: s.id, name: s.name, type: s.type, points_multiplier: s.points_multiplier, order: s.order}
  end
end
