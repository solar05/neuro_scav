defmodule NeuroScav.StatsCounterServer do
  @moduledoc """
  Statistics counter server.
  """
  require Logger

  use GenServer

  alias NeuroScav.{Scavengers, PubSub}

  @counters [:common, :uncommon, :rare, :epic, :legendary, :neuro, :gnome]

  @spec update_counter(:common | :uncommon | :rare | :epic | :legendary | :neuro | :gnome) ::
          :ok | :invalid_counter
  def update_counter(counter) when counter in @counters do
    GenServer.cast(__MODULE__, counter)
  end

  def update_counter(_) do
    :invalid_counter
  end

  @spec gnome_captured() :: :ok
  def gnome_captured(), do: update_counter(:gnome)

  def start_link(_settings) do
    GenServer.start_link(
      __MODULE__,
      %{},
      name: __MODULE__
    )
  end

  @impl true
  def init(_default_state) do
    Logger.info("Statistics counter server started")
    {:ok, Scavengers.get_statistics()}
  end

  @impl true
  def handle_cast(counter, state) do
    new_value = Map.get(state, counter) + 1

    case Scavengers.update_statistics(state, Map.put(%{}, counter, new_value)) do
      {:ok, new_state} ->
        PubSub.broadcast_statistics(new_state)
        {:noreply, new_state}

      {:error, _} ->
        {:noreply, state}
    end
  end
end
