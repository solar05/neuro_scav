defmodule NeuroScav.UserRequestsSupervisor do
  @moduledoc """
  User requests supervisor.
  """
  use Supervisor

  require Logger

  @default_server_timer_seconds 5

  def start_link(_init_arg) do
    Logger.info("User requests supervisor started")
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {NeuroScav.UserRequestsServer,
       %{schedule_timer: @default_server_timer_seconds, initial_state: []}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
