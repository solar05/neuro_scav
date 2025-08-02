defmodule NeuroScav.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NeuroScavWeb.Telemetry,
      NeuroScav.Repo,
      {DNSCluster, query: Application.get_env(:neuro_scav, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NeuroScav.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: NeuroScav.Finch},
      # Start a worker by calling: NeuroScav.Worker.start_link(arg)
      # {NeuroScav.Worker, arg},
      # Start to serve requests, typically the last entry
      NeuroScavWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NeuroScav.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NeuroScavWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
