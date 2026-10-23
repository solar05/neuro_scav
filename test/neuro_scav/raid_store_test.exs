defmodule NeuroScav.RaidStoreTest do
  # not async: the ceiling test fills the table every raid page shares
  use ExUnit.Case, async: false

  alias NeuroScav.{Raid, RaidStore}

  test "keeps a run's raid with its squad, apart from the user's other runs, until it's left" do
    members = [%{name: "Алиса Аврора", rarity: :common}]
    raid = Raid.new(members, [:pmc, :office])
    run = {"store-#{System.unique_integer()}", "run-1"}
    other = put_elem(run, 1, "run-2")

    assert RaidStore.get(run) == nil

    RaidStore.put(run, members, raid)
    assert RaidStore.get(run) == %{members: members, raid: raid}
    assert RaidStore.get(other) == nil

    RaidStore.delete(run)
    assert RaidStore.get(run) == nil
  end

  test "a raid gone stale isn't given, and a sweep drops it, the fresh one stays" do
    user_id = "store-#{System.unique_integer()}"
    fresh = {user_id, "fresh"}
    stale = {user_id, "stale"}

    RaidStore.put(fresh, [], %{})
    # last touched two hours ago (the table holds {key, saved, at})
    two_hours_ago = System.monotonic_time(:millisecond) - :timer.hours(2)
    :ets.insert(RaidStore, {stale, %{members: [], raid: %{}}, two_hours_ago})

    assert RaidStore.get(stale) == nil

    send(RaidStore, :sweep)
    _ = :sys.get_state(RaidStore)

    assert :ets.lookup(RaidStore, stale) == []
    assert RaidStore.get(fresh) == %{members: [], raid: %{}}
  end

  test "past its ceiling it keeps no new run, the ones it keeps go on" do
    user_id = "store-#{System.unique_integer()}"
    on_exit(fn -> :ets.match_delete(RaidStore, {{user_id, :_}, :_, :_}) end)

    kept = {user_id, "kept"}
    RaidStore.put(kept, [], %{step: 0})

    # whatever made them, every room in the table taken
    for i <- 1..(RaidStore.max_runs() - :ets.info(RaidStore, :size)),
        do: RaidStore.put({user_id, "filler-#{i}"}, [], %{})

    refute RaidStore.put({user_id, "new"}, [], %{})
    assert RaidStore.get({user_id, "new"}) == nil

    assert RaidStore.put(kept, [], %{step: 1})
    assert RaidStore.get(kept).raid == %{step: 1}
    assert :ets.info(RaidStore, :size) == RaidStore.max_runs()
  end
end
