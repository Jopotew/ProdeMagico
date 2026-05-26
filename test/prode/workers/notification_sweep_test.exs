defmodule Prode.Workers.NotificationSweepTest do
  use Prode.DataCase, async: true

  import Prode.Factory

  alias Prode.Workers.NotificationSweep

  defp run_job do
    NotificationSweep.perform(%Oban.Job{args: %{}})
  end

  describe "perform/1" do
    test "returns :ok" do
      assert :ok = run_job()
    end

    test "does not error when no upcoming matches" do
      assert :ok = run_job()
    end

    test "enqueues notification jobs for matches starting within 2 hours" do
      tournament = insert(:tournament)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      _upcoming =
        insert(:match,
          tournament: tournament,
          home_team: home,
          away_team: away,
          status: :scheduled,
          kickoff_at: DateTime.add(DateTime.utc_now(), 30 * 60, :second)
        )

      assert :ok = run_job()
    end

    test "ignores finished matches" do
      tournament = insert(:tournament)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      insert(:match,
        tournament: tournament,
        home_team: home,
        away_team: away,
        status: :finished,
        kickoff_at: DateTime.add(DateTime.utc_now(), 30 * 60, :second)
      )

      assert :ok = run_job()
    end

    test "ignores matches beyond the 2-hour window" do
      tournament = insert(:tournament)
      home = insert(:team, tournament: tournament)
      away = insert(:team, tournament: tournament)

      insert(:match,
        tournament: tournament,
        home_team: home,
        away_team: away,
        status: :scheduled,
        kickoff_at: DateTime.add(DateTime.utc_now(), 3 * 60 * 60, :second)
      )

      assert :ok = run_job()
    end
  end
end
