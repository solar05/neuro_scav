defmodule NeuroScav.ScavengersServer do
  @moduledoc """
  Statistics counter server.
  """
  require Logger

  use GenServer

  def start_link(_settings) do
    GenServer.start_link(
      __MODULE__,
      %{},
      name: __MODULE__
    )
  end

  @impl true
  def init(default_state) do
    # add initialization
    Logger.info("Scavenger server started")
    {:ok, default_state}
  end
end
