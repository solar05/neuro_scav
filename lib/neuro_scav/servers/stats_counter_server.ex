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

  Server state is the statistics row (`NeuroScav.Scavengers.Statistics`),
  read from the database whenever the server starts, a restart too. Every
  update is an atomic increment of that row (`Scavengers.increment_statistics/2`),
  so a restart, or another node counting at once, loses nothing; the state
  becomes the row as the database returns it. A write that fails is logged
  and that count is lost; the server goes on.

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

  alias NeuroScav.{PubSub, Scavengers}
  alias NeuroScav.Scavengers.Statistics

  @available_counters [:common, :uncommon, :rare, :epic, :legendary, :neuro, :gnome]

  @doc """
  Get list of available counter types.

  ## Returns

  List of counter atoms that can be incremented.
  """
  @spec available_counters() :: list(atom())
  def available_counters, do: @available_counters

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
  def gnome_captured, do: update_counter(:gnome)

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

  # the row to count in, read afresh: a restarted server picks up every count
  # so far, not what the row held when the server was first started
  @impl true
  def init(%Statistics{id: id}) do
    Logger.info("Statistics counter server started")
    {:ok, Scavengers.get_statistics(id)}
  end

  @impl true
  def handle_cast({:update_multiple_counters, counters}, state),
    do: {:noreply, increment(state, Enum.frequencies(counters))}

  @impl true
  def handle_cast({:update_counter, counter}, state),
    do: {:noreply, increment(state, %{counter => 1})}

  # an atomic increment in the database, then the row as it is now to the
  # statistics page; a failed write loses that count, not the server (a crash
  # at every count while the database is down would take the app down too)
  defp increment(state, counts) do
    case Scavengers.increment_statistics(state, counts) do
      {:ok, statistics} ->
        PubSub.broadcast_statistics(statistics)
        statistics

      {:error, reason} ->
        Logger.warning("Statistics not counted: #{inspect(reason)}")
        state
    end
  end
end
