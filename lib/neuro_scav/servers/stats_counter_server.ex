defmodule NeuroScav.StatsCounterServer do
  @moduledoc """
  Statistics counter server for aggregating scavenger rarity counts.

  This GenServer maintains counters for each scavenger rarity level and special
  events. Counters are updated whenever scavengers are generated or special
  events occur (e.g., gnome captured).

  All counter updates are automatically broadcast to subscribers via PubSub
  with topic "statistics:lobby".

  ## Available Counters

  Seven counter types are tracked:
  - `:common` - Common rarity scavengers generated
  - `:uncommon` - Uncommon rarity scavengers generated
  - `:rare` - Rare rarity scavengers generated
  - `:epic` - Epic rarity scavengers generated
  - `:legendary` - Legendary rarity scavengers generated
  - `:neuro` - AI-generated scavengers
  - `:gnome` - Special gnome capture events

  ## State Management

  Server state is a map where keys are counter atoms and values are integers:
  ```elixir
  %{
    common: 42,
    uncommon: 15,
    rare: 8,
    epic: 2,
    legendary: 1,
    neuro: 5,
    gnome: 0
  }
  ```

  ## Usage Examples

  Update single counter:
      StatsCounterServer.update_counter(:rare)
      # Increments :rare counter by 1

  Update multiple counters:
      StatsCounterServer.update_multiple_counters([:common, :rare, :epic])
      # Increments each specified counter by 1
      # Called when generating a team (5 scavengers)

  Capture gnome:
      StatsCounterServer.gnome_captured()
      # Increments :gnome counter by 1
  """

  require Logger

  use GenServer

  alias NeuroScav.{Scavengers, PubSub}

  @available_counters [:common, :uncommon, :rare, :epic, :legendary, :neuro, :gnome]

  @doc """
  Get list of available counter types.

  ## Returns

  List of counter atoms that can be incremented.
  """
  @spec available_counters() :: list(atom())
  def available_counters(), do: @available_counters

  @doc """
  Increment a single counter by 1.

  Only accepts valid counter types from `available_counters/0`.
  Invalid counters are silently ignored and return `:invalid_counter`.

  ## Parameters

  - `counter` - Counter atom (e.g., `:rare`, `:common`)

  ## Returns

  - `:ok` - Counter was incremented
  - `:invalid_counter` - Counter type not recognized

  ## Examples

      iex> update_counter(:epic)
      :ok

      iex> update_counter(:invalid)
      :invalid_counter
  """
  @spec update_counter(:common | :uncommon | :rare | :epic | :legendary | :neuro | :gnome) ::
          :ok | :invalid_counter
  def update_counter(counter) when counter in @available_counters do
    GenServer.cast(__MODULE__, {:update_counter, counter})
  end

  def update_counter(_) do
    :invalid_counter
  end

  @doc """
  Convenience function to increment the gnome counter.

  Shorthand for `update_counter(:gnome)`.

  ## Returns

  `:ok`
  """
  @spec gnome_captured() :: :ok
  def gnome_captured(), do: update_counter(:gnome)

  @doc """
  Increment multiple counters, each by 1.

  Useful for team scavenger generation where 5 scavengers with
  potentially different rarities are generated simultaneously.

  ## Parameters

  - `counters` - List of counter atoms

  ## Returns

  - `:ok` - All counters were valid and incremented
  - `:invalid_counter` - If list is empty or contains invalid counters

  ## Examples

      # Team of 5 scavengers with rarities
      iex> update_multiple_counters([:common, :rare, :epic, :common, :uncommon])
      :ok

      # Empty list
      iex> update_multiple_counters([])
      :invalid_counter

      # Invalid counter in list
      iex> update_multiple_counters([:rare, :invalid])
      :invalid_counter
  """
  @spec update_multiple_counters([
          :common | :uncommon | :rare | :epic | :legendary | :neuro | :gnome
        ]) :: :ok | :invalid_counter
  def update_multiple_counters([]), do: :invalid_counter

  def update_multiple_counters(counters) do
    if Enum.all?(counters, fn counter -> counter in @available_counters end) do
      GenServer.cast(__MODULE__, {:update_multiple_counters, counters})
    else
      :invalid_counter
    end
  end

  @doc false
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
