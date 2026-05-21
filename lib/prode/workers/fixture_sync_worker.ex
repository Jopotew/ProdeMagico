defmodule Prode.Workers.FixtureSyncWorker do
  @moduledoc """
  Oban worker that pulls fixture data from API-Football and upserts matches.
  Also starts MatchLockers for all upcoming matches after each sync.
  """

  use Oban.Worker, queue: :external_api, max_attempts: 3

  require Logger

  import Ecto.Query, warn: false

  alias Prode.{Matches, Repo, Tournaments}
  alias Prode.Predictions.MatchLockerSupervisor
  alias Prode.Tournaments.{Stage, Team}
  alias Prode.Workers.PointsCalculator

  @world_cup_league 1
  @world_cup_season 2026

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    client = Application.get_env(:prode, :sports_data_client)

    with {:ok, tournament} <- find_tournament(),
         {:ok, fixtures} <- client.list_fixtures(league: @world_cup_league, season: @world_cup_season) do
      stages = load_stages_map(tournament.id)
      Enum.each(fixtures, &sync_fixture(&1, tournament, stages))
      restart_match_lockers()
      Logger.info("FixtureSyncWorker: synced #{length(fixtures)} fixtures")
      :ok
    end
  end

  defp find_tournament do
    case Repo.get_by(Tournaments.Tournament, season: @world_cup_season) do
      nil -> {:error, :tournament_not_found}
      t -> {:ok, t}
    end
  end

  defp load_stages_map(tournament_id) do
    Repo.all(from s in Stage, where: s.tournament_id == ^tournament_id)
    |> Map.new(fn s -> {s.slug, s.id} end)
  end

  defp sync_fixture(fixture, tournament, stages) do
    home_api_id = get_in(fixture, ["teams", "home", "id"])
    away_api_id = get_in(fixture, ["teams", "away", "id"])
    home_name = get_in(fixture, ["teams", "home", "name"])
    away_name = get_in(fixture, ["teams", "away", "name"])

    home_team = upsert_team(tournament.id, home_api_id, home_name)
    away_team = upsert_team(tournament.id, away_api_id, away_name)

    round = get_in(fixture, ["league", "round"])
    stage_id = resolve_stage_id(stages, round, home_team)

    kickoff_at = parse_datetime(get_in(fixture, ["fixture", "date"]))
    prediction_lock_at = DateTime.add(kickoff_at, -15, :minute)

    attrs = %{
      api_football_id: get_in(fixture, ["fixture", "id"]),
      tournament_id: tournament.id,
      stage_id: stage_id,
      home_team_id: home_team.id,
      away_team_id: away_team.id,
      round: round,
      kickoff_at: kickoff_at,
      prediction_lock_at: prediction_lock_at,
      status: parse_status(get_in(fixture, ["fixture", "status", "short"])),
      home_score: get_in(fixture, ["goals", "home"]),
      away_score: get_in(fixture, ["goals", "away"])
    }

    case Matches.upsert_match(attrs) do
      {:ok, match} ->
        if match.status == :finished do
          %{"match_id" => match.id}
          |> PointsCalculator.new()
          |> Oban.insert()
        end

        :ok

      {:error, reason} ->
        Logger.warning("Failed to upsert match #{attrs.api_football_id}: #{inspect(reason)}")
    end
  end

  defp upsert_team(tournament_id, api_id, name) do
    case Repo.get_by(Team, tournament_id: tournament_id, api_football_id: api_id) do
      %Team{} = team ->
        team

      nil ->
        Repo.insert!(%Team{
          tournament_id: tournament_id,
          api_football_id: api_id,
          name: name,
          code: make_code(name)
        })
    end
  end

  defp resolve_stage_id(stages, _round, %Team{group: g}) when is_binary(g) do
    Map.get(stages, "group_#{String.downcase(g)}")
  end

  defp resolve_stage_id(stages, "Round of 16", _team), do: Map.get(stages, "r16")
  defp resolve_stage_id(stages, "Quarter-finals", _team), do: Map.get(stages, "qf")
  defp resolve_stage_id(stages, "Semi-finals", _team), do: Map.get(stages, "sf")
  defp resolve_stage_id(stages, "3rd Place Final", _team), do: Map.get(stages, "third")
  defp resolve_stage_id(stages, "Final", _team), do: Map.get(stages, "final")
  defp resolve_stage_id(_stages, _round, _team), do: nil

  defp parse_datetime(iso_string) do
    {:ok, dt, _offset} = DateTime.from_iso8601(iso_string)
    DateTime.truncate(dt, :second)
  end

  @live_statuses ~w(1H HT 2H ET BT P INT LIVE)
  @finished_statuses ~w(FT AET PEN)

  defp parse_status(short) when short in @live_statuses, do: :live
  defp parse_status(short) when short in @finished_statuses, do: :finished
  defp parse_status("PST"), do: :postponed
  defp parse_status(_), do: :scheduled

  defp make_code(name) do
    name
    |> String.upcase()
    |> String.replace(~r/[^A-Z]/, "")
    |> String.slice(0, 3)
  end

  defp restart_match_lockers do
    Matches.list_upcoming_matches()
    |> Enum.each(&MatchLockerSupervisor.start_locker/1)
  end
end
