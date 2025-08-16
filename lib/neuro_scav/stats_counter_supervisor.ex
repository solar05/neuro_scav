defmodule NeuroScav.StatsCounterSupervisor do
  @moduledoc """
  Statistics supervisor.
  """
  use Supervisor

  require Logger

  alias NeuroScav.Scavengers

  def start_link(_init_arg) do
    Logger.info("Statistics counter supervisor started")
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {NeuroScav.StatsCounterServer, Scavengers.get_statistics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
