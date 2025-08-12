defmodule NeuroScav.ScavengersSupervisor do
  @moduledoc """
  Scavengers supervisor.
  """
  use Supervisor

  require Logger

  def start_link(_init_arg) do
    Logger.info("Scavengers supervisor started")
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {NeuroScav.ScavengersServer, %{}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
