defmodule Prode.Predictions.MatchLockerTest do
  use Prode.DataCase, async: false

  import Prode.Factory

  alias Prode.Matches
  alias Prode.Predictions.MatchLocker

  defp start_locker(match) do
    {:ok, pid} = MatchLocker.start_link(match)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  test "immediately locks a match whose prediction_lock_at is in the past" do
    past = DateTime.add(DateTime.utc_now(:second), -1, :second)

    match =
      insert(:match,
        locked: false,
        prediction_lock_at: past,
        kickoff_at: DateTime.add(past, 15, :minute)
      )

    _pid = start_locker(match)
    # Give the GenServer time to process the :lock message
    Process.sleep(50)

    assert Matches.get_match!(match.id).locked == true
  end

  test "locks a match after the delay elapses" do
    soon = DateTime.add(DateTime.utc_now(:second), 0, :millisecond)

    match =
      insert(:match,
        locked: false,
        prediction_lock_at: soon,
        kickoff_at: DateTime.add(soon, 15, :minute)
      )

    _pid = start_locker(match)
    Process.sleep(100)

    assert Matches.get_match!(match.id).locked == true
  end

  test "second start_link for same match returns already_started" do
    now = DateTime.utc_now(:second)
    match = insert(:match, prediction_lock_at: DateTime.add(now, 1, :hour))

    {:ok, _pid1} = MatchLocker.start_link(match)
    assert {:error, {:already_started, _}} = MatchLocker.start_link(match)
  end
end
