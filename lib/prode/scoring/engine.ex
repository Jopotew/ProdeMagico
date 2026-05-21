defmodule Prode.Scoring.Engine do
  @moduledoc """
  Pure scoring functions. No database access, no side effects.
  Takes structs in, returns integers out.

  Per-match:   group 5/3/0 pts  ×  stage.points_multiplier (1.0 group, 2.0 knockout)
  Bonus:       +10 pts per correct top-scorer or group-winner prediction
  """

  alias Prode.Matches.Match
  alias Prode.Predictions.Prediction
  alias Prode.Tournaments.Stage

  @base_points %{exact: 5, outcome: 3, miss: 0}
  @bonus_points 10

  @doc """
  Returns integer points for a single match prediction.
  Requires `match.stage` to be preloaded (nil falls back to 1.0× multiplier).
  Returns 0 when the match has not been played yet (nil scores).
  """
  @spec calculate_match_points(Prediction.t(), Match.t()) :: non_neg_integer()
  def calculate_match_points(%Prediction{} = prediction, %Match{} = match) do
    base = base_points(prediction, match)
    multiplier = stage_multiplier(match.stage)
    trunc(base * multiplier)
  end

  @doc """
  Returns +10 for correct bonus predictions.

  `:top_scorer` — player must be in actuals list (handles ties).
  `:group_winner` — team ID must match actual winner.
  """
  @spec calculate_bonus_points(:top_scorer, map()) :: non_neg_integer()
  def calculate_bonus_points(:top_scorer, %{
        predicted_player_id: pid,
        actual_top_scorer_ids: actuals
      }) do
    if pid in actuals, do: @bonus_points, else: 0
  end

  @spec calculate_bonus_points(:group_winner, map()) :: non_neg_integer()
  def calculate_bonus_points(:group_winner, %{
        predicted_team_id: tid,
        actual_winner_id: actual
      }) do
    if tid == actual, do: @bonus_points, else: 0
  end

  # --- private ---

  defp base_points(_p, %Match{home_score: nil}), do: 0
  defp base_points(_p, %Match{away_score: nil}), do: 0

  defp base_points(p, m) do
    cond do
      exact_match?(p, m) -> @base_points.exact
      same_outcome?(p, m) -> @base_points.outcome
      true -> @base_points.miss
    end
  end

  defp exact_match?(p, m) do
    p.home_score == m.home_score and p.away_score == m.away_score
  end

  defp same_outcome?(p, m) do
    outcome(p.home_score, p.away_score) == outcome(m.home_score, m.away_score)
  end

  defp outcome(h, a) when h > a, do: :home
  defp outcome(h, a) when h < a, do: :away
  defp outcome(_h, _a), do: :draw

  defp stage_multiplier(%Stage{points_multiplier: mult}) when is_float(mult), do: mult
  defp stage_multiplier(_), do: 1.0
end
