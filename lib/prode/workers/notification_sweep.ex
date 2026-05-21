defmodule Prode.Workers.NotificationSweep do
  @moduledoc """
  Oban cron worker that runs every 15 minutes.
  Finds matches starting within the next 2 hours and enqueues NotificationDispatcher jobs.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query, warn: false

  alias Prode.Matches.Match
  alias Prode.Notifications
  alias Prode.Repo

  @lookahead_seconds 2 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    window_end = DateTime.add(now, @lookahead_seconds, :second)

    upcoming =
      from(m in Match,
        where: m.status == :scheduled,
        where: m.kickoff_at >= ^now,
        where: m.kickoff_at <= ^window_end
      )
      |> Repo.all()

    Enum.each(upcoming, &Notifications.notify_match_start/1)
    :ok
  end
end
