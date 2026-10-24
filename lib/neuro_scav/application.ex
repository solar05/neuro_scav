defmodule NeuroScav.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        NeuroScavWeb.Telemetry,
        NeuroScav.PromEx,
        NeuroScav.Repo,
        {DNSCluster, query: Application.get_env(:neuro_scav, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: NeuroScav.PubSub},
        NeuroScavWeb.Presence,
        # Card battle rooms: one process per invite link
        {Registry, keys: :unique, name: NeuroScav.BattleRegistry},
        {DynamicSupervisor, name: NeuroScav.BattleSupervisor, strategy: :one_for_one},
        # Raids in progress, so a reconnecting page picks its raid up again
        NeuroScav.RaidStore,
        # Share images, drawn one at a time
        NeuroScav.ImageRenderer,
        # Request counts for the /api rate limit
        {NeuroScav.RateLimiter, clean_period: :timer.minutes(1)},
        # Start a worker by calling: NeuroScav.Worker.start_link(arg)
        # {NeuroScav.Worker, arg},
        # Start to serve requests, typically the last entry
        NeuroScavWeb.Endpoint,
        :systemd.ready()
      ]
      |> requests_tree()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NeuroScav.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if Mix.env() == :test do
    defp requests_tree(tree) do
      tree
    end
  else
    defp requests_tree(tree) do
      tree ++
        [
          NeuroScav.UserRequestsSupervisor,
          NeuroScav.ScavengersSupervisor,
          NeuroScav.StatsCounterSupervisor
        ]
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NeuroScavWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
