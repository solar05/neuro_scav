defmodule NeuroScav.UserRequestsSupervisor do
  @moduledoc """
  User requests supervisor.
  """
  use Supervisor

  require Logger

  @default_server_timer_seconds 2

  def start_link(_init_arg) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("User requests supervisor started")

    children = [
      {NeuroScav.UserRequestsServer,
       %{schedule_timer: @default_server_timer_seconds, state: [], client: NeuroScav.Client}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
