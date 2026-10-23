defmodule NeuroScav.RaidMechanicsTest do
  use ExUnit.Case, async: true

  alias NeuroScav.Raid

  @squad [
    %{name: "Алиса Аврора", rarity: :common},
    %{name: "Гена Лена", rarity: :epic},
    %{name: "Дед Мороз", rarity: :legendary}
  ]
  @calm %{weather: :clear, daytime: :morning}

  defp new_raid(members, route, world \\ @calm), do: Raid.new(members, route, nil, world)
  defp actor(raid, index), do: Enum.at(raid.squad, index)

  # one member with every stat at 50, so a chance is plain to work out
  defp plain(route, world) do
    raid = new_raid([%{name: "Алиса Аврора", rarity: :common}], route, world)

    put_in(
      raid.squad,
      Enum.map(raid.squad, &%{&1 | stats: %{strength: 50, agility: 50, luck: 50}})
    )
  end

  describe "keys" do
    test "a key nobody has is locked; its holder opens the way for sure, the item stays theirs" do
      raid = new_raid(@squad, [:trunk, :door_key, :pmc])

      assert %{key: :keycard, locked: true, member: nil} =
               raid |> Raid.choose(0, 100) |> Raid.options() |> Enum.at(2)

      raid = Raid.choose(raid, 0, 1, :keycard)
      finder = actor(raid, hd(raid.stash).owner)
      key = raid |> Raid.options() |> Enum.at(2)
      assert %{key: :keycard, locked: false, chance: 100} = key
      assert key.member.name == finder.name

      raid = Raid.choose(raid, 2, 100, :sj6)
      assert %{outcome: :loot, item: :sj6, used: :keycard} = raid.last
      assert raid.last.member == finder.name
      assert Enum.map(raid.stash, & &1.item) == [:keycard, :sj6]
    end

    test "a fallen holder's key opens nothing" do
      raid = %{new_raid(@squad, [:labs]) | stash: [%{item: :keycard, owner: 0}]}
      assert %{locked: false} = raid |> Raid.options() |> Enum.at(2)

      raid = put_in(raid.squad, List.update_at(raid.squad, 0, &%{&1 | alive: false}))
      assert %{locked: true} = raid |> Raid.options() |> Enum.at(2)
      assert Raid.choose(raid, 2, 1) == raid
    end
  end

  describe "who makes a check" do
    test "a stealthy one is made by the weakest at it" do
      [_storm, sneak] = @squad |> new_raid([:reshala]) |> Raid.options()
      weakest = @squad |> Enum.map(&Raid.card/1) |> Enum.min_by(& &1.stats.agility)

      assert sneak.mode == :weakest
      assert sneak.member.name == weakest.name
    end

    test "one by each takes one roll against everyone: the ones it beats are wounded" do
      raid = new_raid(@squad, [:mines, :pmc])
      [walk, _run] = Raid.options(raid)
      assert walk.mode == :each

      # the chance shown is the weakest one's: a roll within it beats nobody
      assert %{outcome: :pass, member: nil} = Raid.choose(raid, 0, walk.chance).last

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :wounds} = raid.last
      assert Enum.all?(raid.squad, &(&1.wounds == 1))
    end
  end

  describe "consumables" do
    test "a medkit turns a death into a wound, once" do
      raid = %{new_raid(@squad, [:pmc, :pmc, :pmc]) | stash: [%{item: :medkit, owner: 2}]}

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :wound, used: :medkit} = raid.last
      assert length(Raid.alive(raid)) == 3
      assert raid.stash == []

      assert %{outcome: :lose, used: nil} = Raid.choose(raid, 0, 100).last
    end

    test "propital takes a wound away" do
      raid = %{new_raid(@squad, [:obdolbos]) | stash: [%{item: :propital, owner: 0}]}
      [%{member: member}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :spared, used: :propital} = raid.last
      assert actor(raid, member.index).wounds == 0
      assert raid.stash == []
    end

    test "a medkit spares a member the third wound too: it leaves them bleeding, not dead" do
      raid = %{new_raid([hd(@squad)], [:obdolbos]) | stash: [%{item: :medkit, owner: 0}]}
      raid = put_in(raid.squad, List.update_at(raid.squad, 0, &%{&1 | wounds: 2}))

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :wound, used: :medkit} = raid.last
      assert actor(raid, 0).alive
      assert actor(raid, 0).wounds == 2
    end

    test "a fallen member's are no use" do
      raid = %{new_raid(@squad, [:pmc, :pmc]) | stash: [%{item: :medkit, owner: 2}]}
      raid = put_in(raid.squad, List.update_at(raid.squad, 2, &%{&1 | alive: false}))

      assert %{outcome: :lose, used: nil} = Raid.choose(raid, 0, 100).last
    end
  end

  describe "wounds" do
    test "from the second one a member bleeds at every step, the third kills" do
      raid = new_raid([hd(@squad)], [:obdolbos, :obdolbos, :pmc, :obdolbos])

      raid = Raid.choose(raid, 0, 100)
      assert actor(raid, 0).wounds == 1
      refute Raid.bleeding?(actor(raid, 0))

      raid = Raid.choose(raid, 0, 100)
      assert actor(raid, 0).wounds == 2
      assert Raid.bleeding?(actor(raid, 0))

      # a step takes 3 off every stat, to 1 at least
      before = actor(raid, 0).stats
      raid = Raid.choose(raid, 0, 1)

      assert Enum.all?(actor(raid, 0).stats, fn {stat, value} ->
               value == max(before[stat] - 3, 1)
             end)

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :lose} = raid.last
      refute actor(raid, 0).alive
    end

    test "with nobody to bring back a medic patches up the most wounded" do
      raid = @squad |> new_raid([:obdolbos, :medic]) |> Raid.choose(0, 100)
      wounded = raid.last.index

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :heal, index: ^wounded} = raid.last
      assert actor(raid, wounded).wounds == 0
    end
  end

  describe "the world" do
    test "the time of day goes round, three turns each, from where the raid starts" do
      raid = new_raid(@squad, [:office], %{weather: :clear, daytime: :evening})
      times = for turn <- 0..12, do: Raid.world(%{raid | turn: turn}).daytime

      assert times ==
               ~w(evening evening evening night night night morning morning morning day day day evening)a
    end

    test "the weather eases or hardens a stat, the time of day a kind of check" do
      chances = fn route, world ->
        route |> plain(world) |> Raid.options() |> Enum.map(& &1.chance)
      end

      # pmc: a fight with strength at 0, a run with agility at 10 (neither a fight nor hiding)
      assert chances.([:pmc], @calm) == [50, 40]
      # fog: strength -10, agility +5; the day: fights +5
      assert chances.([:pmc], %{weather: :fog, daytime: :day}) == [45, 45]
      # the night: fights -5, hiding (sneaking past Reshala) +10
      assert chances.([:reshala], %{weather: :clear, daytime: :night}) == [30, 55]
      # the morning: a search +5 (a luck check for loot)
      assert chances.([:trunk], @calm) == [55, nil]
    end
  end
end
