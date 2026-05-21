defmodule Prode.Predictions.MatchLockerSupervisor do
  @moduledoc """
  DynamicSupervisor that owns one MatchLocker per upcoming match.
  MatchLockers register themselves in a Registry by match ID, so
  starting a locker for an already-tracked match is a no-op.
  """

  use DynamicSupervisor

  alias Prode.Predictions.MatchLocker

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Starts a MatchLocker for the given match (idempotent)."
  def start_locker(match) do
    case DynamicSupervisor.start_child(__MODULE__, {MatchLocker, match}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
