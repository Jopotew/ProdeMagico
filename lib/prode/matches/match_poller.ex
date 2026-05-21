defmodule Prode.Matches.MatchPoller do
  @moduledoc """
  GenServer that schedules periodic fixture syncs via FixtureSyncWorker.
  Adapts its polling interval based on whether any matches are currently live.
  """

  use GenServer
  require Logger

  alias Prode.Workers.FixtureSyncWorker

  @live_interval_ms :timer.seconds(60)
  @default_interval_ms :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Trigger an immediate sync outside the normal schedule."
  def poll_now do
    GenServer.cast(__MODULE__, :poll_now)
  end

  @impl true
  def init(opts) do
    initial_ms = Keyword.get(opts, :initial_delay_ms, @default_interval_ms)
    schedule_poll(initial_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_cast(:poll_now, state) do
    send(self(), :poll)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    Logger.info("MatchPoller: triggering fixture sync")

    %{}
    |> FixtureSyncWorker.new()
    |> Oban.insert()

    schedule_poll(next_interval_ms())
    {:noreply, state}
  end

  defp next_interval_ms do
    if Prode.Matches.any_live_matches?(), do: @live_interval_ms, else: @default_interval_ms
  end

  defp schedule_poll(ms), do: Process.send_after(self(), :poll, ms)
end
