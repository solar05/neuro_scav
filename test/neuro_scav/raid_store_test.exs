defmodule NeuroScav.RaidStoreTest do
  use ExUnit.Case, async: true

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
end
