defmodule Prode.Predictions.MatchLocker do
  @moduledoc """
  Transient GenServer that fires once at `prediction_lock_at` and sets
  `match.locked = true`. Registered in a Registry by match ID so only
  one locker runs per match.
  """

  use GenServer, restart: :transient
  require Logger

  alias Prode.Matches

  def start_link(match) do
    GenServer.start_link(__MODULE__, match, name: via(match.id))
  end

  @impl true
  def init(match) do
    delay_ms =
      match.prediction_lock_at
      |> DateTime.diff(DateTime.utc_now(), :millisecond)
      |> max(0)

    Process.send_after(self(), :lock, delay_ms)
    {:ok, match}
  end

  @impl true
  def handle_info(:lock, match) do
    Logger.info("MatchLocker: locking predictions for match #{match.id}")
    Matches.lock_match!(match)
    {:stop, :normal, match}
  end

  defp via(match_id) do
    {:via, Registry, {Prode.Predictions.MatchLockerRegistry, match_id}}
  end
end
