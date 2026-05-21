defmodule Prode.Workers.BonusPointsCalculator do
  @moduledoc """
  Calculates bonus points for top scorer and group winner predictions.
  Intended to run at tournament end.
  Args: %{"tournament_id" => id, "kind" => "top_scorer"|"group_winner", "payload" => map}

  For :top_scorer, payload must include "actual_top_scorer_ids" (list of player API IDs).
  For :group_winner, payload must include "group" and "actual_winner_id".
  """

  use Oban.Worker, queue: :scoring, max_attempts: 5

  import Ecto.Query, warn: false

  alias Prode.{Groups, Repo, Scoring.Engine}
  alias Prode.Predictions.BonusPrediction

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tournament_id" => t_id, "kind" => kind_str, "payload" => result_payload}}) do
    kind = String.to_existing_atom(kind_str)

    predictions =
      from(bp in BonusPrediction,
        where: bp.tournament_id == ^t_id,
        where: bp.kind == ^kind,
        where: is_nil(bp.calculated_at)
      )
      |> Repo.all()

    Enum.each(predictions, fn bp ->
      points = score_bonus(kind, bp.payload, result_payload)

      bp
      |> Ecto.Changeset.change(%{
        points_awarded: points,
        calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()
    end)

    affected_user_ids = Enum.map(predictions, & &1.user_id)
    affected_groups = Groups.list_groups_for_users(affected_user_ids)

    Enum.each(affected_groups, fn group ->
      Phoenix.PubSub.broadcast(Prode.PubSub, "group:#{group.id}", {:leaderboard_updated, group.id})
    end)

    :ok
  end

  defp score_bonus(:top_scorer, %{"player_id" => pid}, %{"actual_top_scorer_ids" => actuals}) do
    Engine.calculate_bonus_points(:top_scorer, %{
      predicted_player_id: pid,
      actual_top_scorer_ids: actuals
    })
  end

  defp score_bonus(:group_winner, %{"team_id" => tid}, %{"actual_winner_id" => winner}) do
    Engine.calculate_bonus_points(:group_winner, %{
      predicted_team_id: tid,
      actual_winner_id: winner
    })
  end

  defp score_bonus(_, _, _), do: 0
end
