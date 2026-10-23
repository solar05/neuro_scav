defmodule NeuroScav.RaidStore do
  @moduledoc """
  Raids in progress, so a raid page that reconnects (a phone back from the
  background, a dropped network) picks its raid up again instead of starting
  over. A raid is kept by its user and run, `{user_id, run}`: the run names
  the page's raid in its address, so each tab has its own and a link someone
  shares picks up nothing of theirs.

  Kept in memory (ETS), each with its squad: a raid lives `@ttl` after its
  last step, a sweep every `@sweep` drops the stale ones. The server only
  owns the table: reads and writes go straight to it.
  """

  # ponytail: in memory, so a restart (a deploy) still loses the raids; a signed
  # raid in the browser's localStorage would survive it if that matters

  use GenServer

  @table __MODULE__
  @ttl :timer.hours(1)
  @sweep :timer.minutes(10)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Keeps a run's raid with its squad."
  @spec put({String.t(), String.t()}, [map()], map()) :: true
  def put(key, members, raid),
    do: :ets.insert(@table, {key, %{members: members, raid: raid}, now()})

  @doc "A run's raid with its squad, `%{members, raid}`, nil when there's none or it's stale."
  @spec get({String.t(), String.t()}) :: %{members: [map()], raid: map()} | nil
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, saved, at}] -> if now() - at < @ttl, do: saved
      [] -> nil
    end
  end

  @doc "Forgets a run's raid: the squad has left it."
  @spec delete({String.t(), String.t()}) :: true
  def delete(key), do: :ets.delete(@table, key)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    stale = now() - @ttl
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", stale}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep)

  defp now, do: System.monotonic_time(:millisecond)
end
