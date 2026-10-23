defmodule NeuroScav.RaidStoreTest do
  use ExUnit.Case, async: true

  alias NeuroScav.{Raid, RaidStore}

  test "keeps a user's raid with its squad" do
    members = [%{name: "Алиса Аврора", rarity: :common}]
    raid = Raid.new(members, [:pmc, :office])
    user_id = "store-#{System.unique_integer()}"

    assert RaidStore.get(user_id) == nil

    RaidStore.put(user_id, members, raid)
    assert RaidStore.get(user_id) == %{members: members, raid: raid}
  end
end
