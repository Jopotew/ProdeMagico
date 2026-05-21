defmodule Prode.External.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Prode.External.RateLimiter

  # Start an unnamed instance so we don't collide with the app-level one.
  defp start_limiter(opts \\ []) do
    opts = Keyword.merge([bucket_size: 3, refill_ms: 60_000, name: nil], opts)
    {:ok, pid} = RateLimiter.start_link(opts)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  test "returns :ok while tokens are available" do
    pid = start_limiter(bucket_size: 2)
    assert :ok = RateLimiter.acquire(pid)
    assert :ok = RateLimiter.acquire(pid)
  end

  test "returns rate_limited when bucket is empty" do
    pid = start_limiter(bucket_size: 1)
    assert :ok = RateLimiter.acquire(pid)
    assert {:error, :rate_limited} = RateLimiter.acquire(pid)
  end

  test "tokens are replenished after refill message" do
    pid = start_limiter(bucket_size: 1)
    assert :ok = RateLimiter.acquire(pid)
    assert {:error, :rate_limited} = RateLimiter.acquire(pid)

    send(pid, :refill)
    # Sync flush ensures the cast is processed before we continue.
    :sys.get_state(pid)

    assert :ok = RateLimiter.acquire(pid)
  end

  test "bucket does not exceed max size on refill" do
    pid = start_limiter(bucket_size: 2)
    # Bucket is already full; refill should cap at bucket_size.
    send(pid, :refill)
    :sys.get_state(pid)

    assert :ok = RateLimiter.acquire(pid)
    assert :ok = RateLimiter.acquire(pid)
    assert {:error, :rate_limited} = RateLimiter.acquire(pid)
  end

  test "blocks when API remaining is below safety threshold" do
    pid = start_limiter()
    RateLimiter.update_api_remaining(150, pid)
    :sys.get_state(pid)

    assert {:error, :rate_limited} = RateLimiter.acquire(pid)
  end

  test "allows through when API remaining is above safety threshold" do
    pid = start_limiter()
    RateLimiter.update_api_remaining(500, pid)
    :sys.get_state(pid)

    assert :ok = RateLimiter.acquire(pid)
  end

  test "nil api_remaining does not block requests" do
    pid = start_limiter()
    # api_remaining starts nil — should not block
    assert :ok = RateLimiter.acquire(pid)
  end
end
