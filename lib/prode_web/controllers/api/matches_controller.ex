defmodule ProdeWeb.Api.MatchesController do
  use ProdeWeb, :controller

  alias Prode.Matches
  alias Prode.Predictions
  alias Prode.Repo

  def index(conn, %{"tournament_id" => t_id}) do
    matches = Matches.list_matches_for_tournament(t_id) |> Repo.preload([:home_team, :away_team, :stage])
    json(conn, %{data: Enum.map(matches, &match_json/1)})
  end

  def index(conn, _params) do
    json(conn, %{error: "tournament_id is required"})
  end

  def show(conn, %{"id" => id}) do
    match = Matches.get_match!(id) |> Repo.preload([:home_team, :away_team, :stage])
    json(conn, %{data: match_json(match)})
  rescue
    Ecto.NoResultsError -> send_resp(conn, 404, ~s({"error":"not found"}))
  end

  def predict(conn, %{"id" => match_id} = params) do
    user = conn.assigns.current_user

    attrs = %{
      user_id: user.id,
      match_id: match_id,
      home_score: params["home_score"],
      away_score: params["away_score"]
    }

    case Predictions.upsert_prediction(attrs) do
      {:ok, prediction} ->
        conn
        |> put_status(200)
        |> json(%{data: prediction_json(prediction)})

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> json(%{error: format_errors(changeset)})
    end
  end

  defp match_json(m) do
    %{
      id: m.id,
      round: m.round,
      kickoff_at: m.kickoff_at,
      prediction_lock_at: m.prediction_lock_at,
      locked: m.locked,
      status: m.status,
      home_score: m.home_score,
      away_score: m.away_score,
      home_team: team_json(m.home_team),
      away_team: team_json(m.away_team),
      stage: stage_ref(m.stage)
    }
  end

  defp team_json(nil), do: nil
  defp team_json(t), do: %{id: t.id, name: t.name, code: t.code, group: t.group}

  defp stage_ref(nil), do: nil
  defp stage_ref(s), do: %{id: s.id, name: s.name, type: s.type}

  defp prediction_json(p) do
    %{id: p.id, match_id: p.match_id, home_score: p.home_score, away_score: p.away_score}
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
