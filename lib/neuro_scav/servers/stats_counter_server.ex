defmodule NeuroScav.StatsCounterServer do
  @moduledoc """
  Statistics counter server.
  """
  require Logger

  use GenServer

  alias NeuroScav.{Scavengers, PubSub}

  @available_counters [:common, :uncommon, :rare, :epic, :legendary, :neuro, :gnome]

  @spec available_counters() :: :common | :uncommon | :rare | :epic | :legendary | :neuro | :gnome
  def available_counters(), do: @available_counters

  @spec update_counter(:common | :uncommon | :rare | :epic | :legendary | :neuro | :gnome) ::
          :ok | :invalid_counter
  def update_counter(counter) when counter in @available_counters do
    GenServer.cast(__MODULE__, {:update_counter, counter})
  end

  def update_counter(_) do
    :invalid_counter
  end

  @spec gnome_captured() :: :ok
  def gnome_captured(), do: update_counter(:gnome)

  @spec update_miltiple_counters([
          :common | :uncommon | :rare | :epic | :legendary | :neuro | :gnome
        ]) :: :ok | :invalid_counter
  def update_miltiple_counters([]), do: :invalid_counter

  def update_miltiple_counters(counters) do
    if Enum.all?(counters, fn counter -> counter in @available_counters end) do
      GenServer.cast(__MODULE__, {:update_multiple_counters, counters})
    else
      :invalid_counter
    end
  end

  def start_link(default_state) do
    GenServer.start_link(
      __MODULE__,
      default_state,
      name: __MODULE__
    )
  end

  @impl true
  def init(default_state) do
    Logger.info("Statistics counter server started")
    {:ok, default_state}
  end

  @impl true
  def handle_cast({:update_multiple_counters, counters}, state) do
    summarized_counters = Enum.frequencies(counters)

    new_statistics =
      Enum.reduce(summarized_counters, %{}, fn {counter, increased_value}, acc ->
        new_value = Map.get(state, counter) + increased_value
        Map.put(acc, counter, new_value)
      end)

    {:ok, new_state} = Scavengers.update_statistics(state, new_statistics)
    PubSub.broadcast_statistics(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_counter, counter}, state) do
    new_value = Map.get(state, counter) + 1

    {:ok, new_state} = Scavengers.update_statistics(state, Map.put(%{}, counter, new_value))
    PubSub.broadcast_statistics(new_state)

    {:noreply, new_state}
  end
end
