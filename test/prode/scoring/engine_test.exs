defmodule Prode.Scoring.EngineTest do
  use ExUnit.Case, async: true

  alias Prode.Matches.Match
  alias Prode.Predictions.Prediction
  alias Prode.Scoring.Engine
  alias Prode.Tournaments.Stage

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp group, do: %Stage{type: :group, points_multiplier: 1.0}
  defp knockout, do: %Stage{type: :knockout, points_multiplier: 2.0}

  defp match(home, away, stage \\ nil),
    do: %Match{home_score: home, away_score: away, stage: stage}

  defp pred(home, away), do: %Prediction{home_score: home, away_score: away}

  # ── Per-match: group stage ───────────────────────────────────────────────────

  describe "calculate_match_points/2 — group stage (1×)" do
    test "exact score → 5 pts" do
      assert 5 == Engine.calculate_match_points(pred(2, 1), match(2, 1, group()))
    end

    test "correct outcome home win, wrong score → 3 pts" do
      assert 3 == Engine.calculate_match_points(pred(1, 0), match(3, 1, group()))
    end

    test "correct outcome away win, wrong score → 3 pts" do
      assert 3 == Engine.calculate_match_points(pred(0, 2), match(0, 5, group()))
    end

    test "correct outcome draw, wrong score → 3 pts" do
      assert 3 == Engine.calculate_match_points(pred(1, 1), match(2, 2, group()))
    end

    test "predicted home win, actual away win → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(2, 1), match(1, 3, group()))
    end

    test "predicted home win, actual draw → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(2, 0), match(1, 1, group()))
    end

    test "predicted draw, actual home win → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(0, 0), match(1, 0, group()))
    end

    test "predicted away win, actual draw → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(0, 1), match(0, 0, group()))
    end

    test "0-0 exact score → 5 pts" do
      assert 5 == Engine.calculate_match_points(pred(0, 0), match(0, 0, group()))
    end
  end

  # ── Per-match: knockout stage ─────────────────────────────────────────────────

  describe "calculate_match_points/2 — knockout stage (2×)" do
    test "exact score → 10 pts" do
      assert 10 == Engine.calculate_match_points(pred(2, 1), match(2, 1, knockout()))
    end

    test "correct outcome, wrong score → 6 pts" do
      assert 6 == Engine.calculate_match_points(pred(1, 0), match(2, 0, knockout()))
    end

    test "wrong outcome → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(2, 1), match(1, 2, knockout()))
    end

    test "exact draw prediction, actual draw different score → 6 pts" do
      assert 6 == Engine.calculate_match_points(pred(1, 1), match(3, 3, knockout()))
    end
  end

  # ── Stage fallback ────────────────────────────────────────────────────────────

  describe "calculate_match_points/2 — nil stage (falls back to 1.0×)" do
    test "exact score with nil stage → 5 pts" do
      assert 5 == Engine.calculate_match_points(pred(1, 0), match(1, 0, nil))
    end

    test "correct outcome with nil stage → 3 pts" do
      assert 3 == Engine.calculate_match_points(pred(1, 0), match(2, 0, nil))
    end

    test "miss with nil stage → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(1, 0), match(0, 1, nil))
    end
  end

  # ── Unfinished match ──────────────────────────────────────────────────────────

  describe "calculate_match_points/2 — match not yet played" do
    test "nil home score → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(2, 1), match(nil, 1, group()))
    end

    test "nil away score → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(2, 1), match(2, nil, group()))
    end

    test "both scores nil → 0 pts" do
      assert 0 == Engine.calculate_match_points(pred(2, 1), match(nil, nil, knockout()))
    end
  end

  # ── Idempotency ───────────────────────────────────────────────────────────────

  describe "idempotency" do
    test "calling calculate_match_points twice returns the same result" do
      p = pred(2, 1)
      m = match(2, 1, group())
      assert Engine.calculate_match_points(p, m) == Engine.calculate_match_points(p, m)
    end

    test "different prediction structs with same values are equal" do
      m = match(1, 0, knockout())

      assert Engine.calculate_match_points(pred(1, 0), m) ==
               Engine.calculate_match_points(%Prediction{home_score: 1, away_score: 0}, m)
    end
  end

  # ── Table-driven: all outcome × stage combinations ────────────────────────────

  @cases [
    # {label, pred_h, pred_a, match_h, match_a, stage, expected}
    {"group exact", 2, 1, 2, 1, :group, 5},
    {"group outcome home", 2, 0, 3, 0, :group, 3},
    {"group outcome away", 0, 1, 0, 2, :group, 3},
    {"group outcome draw", 1, 1, 0, 0, :group, 3},
    {"group miss hw->aw", 2, 1, 1, 2, :group, 0},
    {"group miss hw->draw", 1, 0, 0, 0, :group, 0},
    {"group miss aw->hw", 0, 2, 2, 0, :group, 0},
    {"group miss aw->draw", 0, 1, 1, 1, :group, 0},
    {"group miss draw->hw", 0, 0, 1, 0, :group, 0},
    {"group miss draw->aw", 0, 0, 0, 1, :group, 0},
    {"knockout exact", 1, 0, 1, 0, :knockout, 10},
    {"knockout outcome home", 1, 0, 2, 0, :knockout, 6},
    {"knockout outcome away", 0, 1, 0, 3, :knockout, 6},
    {"knockout outcome draw", 2, 2, 1, 1, :knockout, 6},
    {"knockout miss hw->aw", 2, 0, 0, 1, :knockout, 0},
    {"knockout miss hw->draw", 3, 1, 0, 0, :knockout, 0},
    {"knockout miss aw->hw", 0, 1, 1, 0, :knockout, 0},
    {"knockout miss draw->hw", 1, 1, 2, 1, :knockout, 0}
  ]

  for {label, ph, pa, mh, ma, stage_type, expected} <- @cases do
    @ph ph
    @pa pa
    @mh mh
    @ma ma
    @stage_type stage_type
    @expected expected

    test "table: #{label}" do
      stage = if @stage_type == :group, do: group(), else: knockout()
      assert @expected == Engine.calculate_match_points(pred(@ph, @pa), match(@mh, @ma, stage))
    end
  end

  # ── Bonus: top scorer ─────────────────────────────────────────────────────────

  describe "calculate_bonus_points/2 — top scorer" do
    test "correct single top scorer → 10 pts" do
      assert 10 ==
               Engine.calculate_bonus_points(:top_scorer, %{
                 predicted_player_id: 42,
                 actual_top_scorer_ids: [42]
               })
    end

    test "wrong top scorer → 0 pts" do
      assert 0 ==
               Engine.calculate_bonus_points(:top_scorer, %{
                 predicted_player_id: 7,
                 actual_top_scorer_ids: [42]
               })
    end

    test "correct when multiple players tied for top scorer" do
      assert 10 ==
               Engine.calculate_bonus_points(:top_scorer, %{
                 predicted_player_id: 7,
                 actual_top_scorer_ids: [42, 7, 99]
               })
    end

    test "wrong when multiple tied scorers and not among them" do
      assert 0 ==
               Engine.calculate_bonus_points(:top_scorer, %{
                 predicted_player_id: 1,
                 actual_top_scorer_ids: [42, 7, 99]
               })
    end
  end

  # ── Bonus: group winner ───────────────────────────────────────────────────────

  describe "calculate_bonus_points/2 — group winner" do
    test "correct group winner → 10 pts" do
      assert 10 ==
               Engine.calculate_bonus_points(:group_winner, %{
                 predicted_team_id: "arg",
                 actual_winner_id: "arg"
               })
    end

    test "wrong group winner → 0 pts" do
      assert 0 ==
               Engine.calculate_bonus_points(:group_winner, %{
                 predicted_team_id: "bra",
                 actual_winner_id: "arg"
               })
    end
  end
end
