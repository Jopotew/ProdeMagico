defmodule Prode.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ProdeWeb.Telemetry,
        Prode.Repo,
        {DNSCluster, query: Application.get_env(:prode, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Prode.PubSub},
        {Oban, Application.fetch_env!(:prode, Oban)},
        Prode.External.RateLimiter,
        {Registry, keys: :unique, name: Prode.Predictions.MatchLockerRegistry},
        Prode.Predictions.MatchLockerSupervisor
      ] ++ match_poller_children() ++ [ProdeWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Prode.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp match_poller_children do
    if Application.get_env(:prode, :start_match_poller, true) do
      [Prode.Matches.MatchPoller]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ProdeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
