defmodule NeuroScav.StatsCounterServer do
  @moduledoc """
  Statistics counter server.
  """
  require Logger

  use GenServer

  @spec update_counter(:neuro_scav | :gnome) :: :ok | :invalid_counter
  def update_counter(:neuro_scav) do
    GenServer.cast(__MODULE__, :neuro)
  end

  def update_counter(:gnome) do
    GenServer.cast(__MODULE__, :gnome)
  end

  def update_counter(_) do
    :invalid_counter
  end

  def start_link(_settings) do
    GenServer.start_link(
      __MODULE__,
      %{},
      name: __MODULE__
    )
  end

  @impl true
  def init(default_state) do
    Logger.info("Statistics counter server started")
    {:ok, default_state}
  end

  # def handle_cast(counter, state) do
  #   # [stats] = Statistics.get_all()
  #   # stats = Statistics.update_counter(counter)
  #   # {:ok, _} = Statisctics.update(stats)

  #   {:noreply, state}
  # end
end
