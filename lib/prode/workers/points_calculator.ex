defmodule Prode.Workers.PointsCalculator do
  @moduledoc """
  Calculates and persists match points for every prediction on a finished match.
  Idempotent: predictions with a non-nil `calculated_at` are skipped.
  Broadcasts `{:leaderboard_updated, group_id}` to all groups affected.
  """

  use Oban.Worker, queue: :scoring, max_attempts: 5

  import Ecto.Query, warn: false

  alias Prode.{Groups, Matches, Repo, Scoring.Engine}
  alias Prode.Predictions.Prediction

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"match_id" => match_id}}) do
    match = Matches.get_match!(match_id) |> Repo.preload(:stage)

    if match.status == :finished do
      predictions =
        from(p in Prediction,
          where: p.match_id == ^match_id,
          where: is_nil(p.calculated_at)
        )
        |> Repo.all()

      Enum.each(predictions, fn pred ->
        points = Engine.calculate_match_points(pred, match)

        pred
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

      :telemetry.execute([:prode, :points, :calculated], %{count: length(predictions)}, %{
        match_id: match_id
      })

      :ok
    else
      {:snooze, 60}
    end
  end
end
