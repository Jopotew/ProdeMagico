defmodule Prode.External.RateLimiter do
  @moduledoc """
  Token-bucket GenServer that gates all API-Football HTTP calls.

  Each `acquire/2` call consumes one token. Tokens refill at a fixed
  interval (default 1 per 2 s = 30/min). Additionally, once the API
  reports fewer than `@safety_threshold` requests remaining in the daily
  quota, all further requests are blocked until the counter is updated.
  """

  use GenServer
  require Logger

  @safety_threshold 200
  @default_bucket_size 10
  @default_refill_ms 2_000

  defstruct [:bucket_size, :refill_ms, tokens: @default_bucket_size, api_remaining: nil]

  # --- Public API ---

  def start_link(opts \\ []) do
    {name_opt, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name_opt, do: [name: name_opt], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc "Consume one token. Returns `:ok` or `{:error, :rate_limited}`."
  def acquire(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :acquire, timeout)
  end

  @doc "Notify the limiter of the daily quota remaining (from API response headers)."
  def update_api_remaining(remaining, server \\ __MODULE__) when is_integer(remaining) do
    GenServer.cast(server, {:update_api_remaining, remaining})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    bucket_size = Keyword.get(opts, :bucket_size, @default_bucket_size)
    refill_ms = Keyword.get(opts, :refill_ms, @default_refill_ms)
    schedule_refill(refill_ms)

    {:ok,
     %__MODULE__{
       bucket_size: bucket_size,
       refill_ms: refill_ms,
       tokens: bucket_size
     }}
  end

  @impl true
  def handle_call(:acquire, _from, state) do
    cond do
      api_limit_low?(state) ->
        {:reply, {:error, :rate_limited}, state}

      state.tokens > 0 ->
        {:reply, :ok, %{state | tokens: state.tokens - 1}}

      true ->
        {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl true
  def handle_cast({:update_api_remaining, remaining}, state) do
    if remaining < @safety_threshold do
      Logger.warning("API-Football daily quota low: #{remaining} requests remaining")
    end

    {:noreply, %{state | api_remaining: remaining}}
  end

  @impl true
  def handle_info(:refill, state) do
    new_tokens = min(state.tokens + 1, state.bucket_size)
    schedule_refill(state.refill_ms)
    {:noreply, %{state | tokens: new_tokens}}
  end

  defp api_limit_low?(%{api_remaining: nil}), do: false
  defp api_limit_low?(%{api_remaining: n}), do: n < @safety_threshold

  defp schedule_refill(ms), do: Process.send_after(self(), :refill, ms)
end
