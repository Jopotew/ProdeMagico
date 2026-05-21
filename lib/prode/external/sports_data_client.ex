defmodule Prode.External.SportsDataClient do
  @moduledoc """
  Behaviour for the sports data provider (API-Football v3).
  All external calls go through implementations of this behaviour so that
  tests can swap in a Mox mock without touching the network.
  """

  @type fixture_id :: integer()
  @type opts :: keyword()

  @callback get_status() :: {:ok, map()} | {:error, term()}
  @callback list_fixtures(opts()) :: {:ok, list(map())} | {:error, term()}
  @callback get_fixture(fixture_id()) :: {:ok, map()} | {:error, term()}
  @callback list_top_scorers(opts()) :: {:ok, list(map())} | {:error, term()}
end
