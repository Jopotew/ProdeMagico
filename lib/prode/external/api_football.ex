defmodule Prode.External.ApiFootball do
  @moduledoc false
  @behaviour Prode.External.SportsDataClient

  require Logger

  alias Prode.External.RateLimiter

  @default_base_url "https://v3.football.api-sports.io"

  # --- SportsDataClient callbacks ---

  @impl true
  def get_status, do: request(:get, "/status", [])

  @impl true
  def list_fixtures(opts), do: request(:get, "/fixtures", opts)

  @impl true
  def get_fixture(fixture_id) when is_integer(fixture_id) do
    case request(:get, "/fixtures", id: fixture_id) do
      {:ok, [fixture | _]} -> {:ok, fixture}
      {:ok, []} -> {:error, :not_found}
      error -> error
    end
  end

  @impl true
  def list_top_scorers(opts), do: request(:get, "/players/topscorers", opts)

  # --- Private helpers ---

  defp request(method, path, params) do
    with :ok <- RateLimiter.acquire() do
      api_key = Application.get_env(:prode, :api_football_key, "")
      base_url = Application.get_env(:prode, :api_football_base_url, @default_base_url)

      req = Req.new(base_url: base_url, headers: [{"x-apisports-key", api_key}], retry: false)

      case Req.request(req, method: method, url: path, params: params) do
        {:ok, %Req.Response{status: 200, headers: headers, body: body}} ->
          update_quota(headers)
          {:ok, Map.get(body, "response", [])}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("API-Football request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp update_quota(headers) do
    value =
      Enum.find_value(headers, fn
        {"x-ratelimit-requests-remaining", v} -> v
        _ -> nil
      end)

    with true <- is_binary(value),
         {remaining, _} <- Integer.parse(value) do
      RateLimiter.update_api_remaining(remaining)
    end

    :ok
  end
end
