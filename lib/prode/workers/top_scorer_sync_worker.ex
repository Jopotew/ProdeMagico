defmodule Prode.Workers.TopScorerSyncWorker do
  @moduledoc """
  Daily sync of top scorer standings from API-Football.
  Stores current leaders in the application cache so BonusPointsCalculator
  can resolve winners without hitting the API again.
  """

  use Oban.Worker, queue: :external_api, max_attempts: 3

  require Logger

  alias Prode.Tournaments

  @world_cup_league 1
  @world_cup_season 2026

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    client = Application.get_env(:prode, :sports_data_client)

    case client.list_top_scorers(league: @world_cup_league, season: @world_cup_season) do
      {:ok, scorers} ->
        top_ids = extract_top_scorer_ids(scorers)
        :persistent_term.put({:prode, :top_scorer_ids}, top_ids)
        Logger.info("TopScorerSyncWorker: cached #{length(top_ids)} top scorer(s)")
        :ok

      {:error, reason} ->
        Logger.warning("TopScorerSyncWorker: failed to fetch top scorers: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Returns the current top scorer player IDs from cache, or [] if not yet synced."
  def current_top_scorer_ids do
    :persistent_term.get({:prode, :top_scorer_ids}, [])
  end

  @doc "Returns the winner team API ID for a group from cache, or nil."
  def group_winner_id(group_letter) do
    :persistent_term.get({:prode, :group_winner, group_letter}, nil)
  end

  @doc "Stores group winner IDs (called after group stage finishes)."
  def store_group_winner(group_letter, team_api_id) do
    :persistent_term.put({:prode, :group_winner, group_letter}, team_api_id)
  end

  # Finds the max goal count, then returns all player IDs tied at that count.
  defp extract_top_scorer_ids([]), do: []

  defp extract_top_scorer_ids(scorers) do
    max_goals =
      scorers
      |> Enum.map(&get_in(&1, ["statistics", Access.at(0), "goals", "total"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> 0 end)

    scorers
    |> Enum.filter(fn s ->
      get_in(s, ["statistics", Access.at(0), "goals", "total"]) == max_goals
    end)
    |> Enum.map(fn s -> get_in(s, ["player", "id"]) end)
    |> Enum.reject(&is_nil/1)
  end

  # Ensures the tournament has a bonus_predictions_lock_at set (kickoff of first match).
  def ensure_bonus_lock_set(tournament_id) do
    tournament = Tournaments.get_tournament!(tournament_id)

    if is_nil(tournament.bonus_predictions_lock_at) do
      Tournaments.set_bonus_predictions_lock!(tournament)
    end
  end
end
