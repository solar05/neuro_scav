defmodule NeuroScav.RaidMechanicsTest do
  use ExUnit.Case, async: true

  alias NeuroScav.Raid

  @squad [
    %{name: "Алиса Аврора", rarity: :common},
    %{name: "Гена Лена", rarity: :epic},
    %{name: "Дед Мороз", rarity: :legendary}
  ]
  @calm %{weather: :clear, daytime: :morning}

  defp new_raid(members, route, world \\ @calm), do: Raid.new(members, route, world)
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

  describe "gifts" do
    test "a gift nobody has is locked; its holder hands it over for good, a sure success" do
      raid = @squad |> new_raid([:pmc, :medic, :pmc]) |> Raid.choose(0, 100)
      [fallen] = Enum.reject(raid.squad, & &1.alive)
      assert %{give: :ledx, locked: true, member: nil} = raid |> Raid.options() |> Enum.at(1)

      holder = hd(Raid.alive(raid))

      raid = %{
        raid
        | stash: [%{item: :ledx, owner: holder.index}, %{item: :sj6, owner: holder.index}]
      }

      assert %{give: :ledx, locked: false, chance: 100, reward: :revive, retreat: false} =
               gift = raid |> Raid.options() |> Enum.at(1)

      assert gift.member.index == holder.index

      raid = Raid.choose(raid, 1, 100)
      assert %{outcome: :revive, used: :ledx} = raid.last
      assert raid.last.member == fallen.name
      assert Enum.map(raid.stash, & &1.item) == [:sj6]
    end

    test "a quest's item handed over brings the trader's reward a few nodes later" do
      raid = %{
        new_raid(@squad, [:prapor_quest, :office, :office, :pmc])
        | stash: [%{item: :teapot, owner: 0}]
      }

      raid = Raid.choose(raid, 1, 100)
      assert %{outcome: :pass, used: :teapot, follow_up: :prapor_reward} = raid.last
      assert raid.stash == []

      raid = Raid.choose(raid, 1, 1)
      assert Raid.event(raid) == :prapor_reward and Raid.at(raid) == {2, 0}
    end
  end

  describe "who makes a check" do
    test "a stealthy one is made by the weakest at it" do
      [_listen, sneak] = @squad |> new_raid([:footsteps]) |> Raid.options()
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

      # pmc: a fight with strength at -15, a run with agility at -10 (neither a fight nor hiding)
      assert chances.([:pmc], @calm) == [65, 60]
      # fog: strength -10, agility +5; the day: fights +5
      assert chances.([:pmc], %{weather: :fog, daytime: :day}) == [60, 65]
      # the night: fights -5, hiding (sneaking past the Goons) +10
      assert chances.([:goons], %{weather: :clear, daytime: :night}) == [15, 85, nil]
      # a rainbow: luck +10
      assert chances.([:trunk], %{weather: :rainbow, daytime: :evening}) == [60, nil]
      # the morning: a search +5 (a luck check for loot)
      assert chances.([:trunk], @calm) == [55, nil]
    end
  end

  describe "searches" do
    test "each look finds an item for the luckiest, the squad stays, the next one riskier" do
      raid = new_raid(@squad, [:abandoned_store, :pmc])
      luckiest = Enum.max_by(raid.squad, & &1.stats.luck)

      # the first look's danger is 10%, the morning eases searching by 5
      assert [%{search: 0, member: ^luckiest, chance: 95, reward: :loot}, %{leave: true}] =
               Raid.options(raid)

      raid = Raid.choose(raid, 0, 1, :sj6)
      assert %{outcome: :found, item: :sj6, member: name} = raid.last
      assert name == luckiest.name
      assert %{searched: 1, stash: [%{item: :sj6, owner: owner}]} = raid
      assert Raid.at(raid) == {0, 0}
      assert owner == luckiest.index
      assert [%{search: 1, chance: 80}, _leave] = Raid.options(raid)

      raid = Raid.choose(raid, 1, 1)
      assert %{outcome: :left, retreat: nil} = raid.last
      assert Raid.at(raid) == {1, 0} and raid.searched == 0
    end

    test "a look that fails hurts the searcher on luck, and the squad moves on" do
      raid = new_raid(@squad, [:dorm_room, :pmc])
      luckiest = Enum.max_by(raid.squad, & &1.stats.luck)

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :wound, stat: :luck} = raid.last
      assert actor(raid, luckiest.index).stats.luck == luckiest.stats.luck - Raid.stat_step()
      assert Raid.at(raid) == {1, 0} and raid.searched == 0
    end
  end

  describe "traits" do
    # members with these traits, every stat of each at its value
    defp squad(route, members) do
      raid = new_raid(Enum.take(@squad, length(members)), route)

      put_in(
        raid.squad,
        Enum.zip_with(raid.squad, members, fn member, {trait, value} ->
          %{member | trait: trait, stats: %{strength: value, agility: value, luck: value}}
        end)
      )
    end

    defp name(raid, index), do: actor(raid, index).name

    test "a trait comes from the name, the same every time" do
      raid = new_raid(@squad, [:pmc])
      for member <- raid.squad, do: assert(member.trait == Raid.trait(member.name))
      assert Raid.trait("Дед Мороз") in Raid.traits()
    end

    test "nobody acts on their own unless the quirk roll says so" do
      raid = squad([:office, :pmc], [{:greedy, 50}])
      assert %{outcome: :safe, quirk: nil} = Raid.choose(raid, 1, 1, :sj6, 26).last
      assert %{outcome: :safe, quirk: nil} = Raid.choose(raid, 1, 1).last
    end

    test "a greedy one goes for the loot whatever the squad chose, one more box too" do
      raid = squad([:office, :pmc], [{:greedy, 50}, {:coward, 70}])
      greedy = name(raid, 0)

      assert %{outcome: :loot, member: ^greedy, quirk: {:greedy, ^greedy}} =
               Raid.choose(raid, 1, 1, :sj6, 1).last

      raid = squad([:abandoned_store, :pmc], [{:greedy, 50}, {:coward, 70}])
      raid = Raid.choose(raid, 1, 1, :sj6, 1)
      assert %{outcome: :found, member: ^greedy, quirk: {:greedy, ^greedy}} = raid.last
      assert Raid.at(raid) == {0, 0} and raid.searched == 1
    end

    test "a psycho goes for the fight" do
      raid = squad([:pmc, :office], [{:coward, 60}, {:psycho, 40}])
      psycho = name(raid, 1)
      raid = Raid.choose(raid, 1, 100, :sj6, 1)

      assert %{outcome: :lose, stat: :strength, member: ^psycho, quirk: {:psycho, ^psycho}} =
               raid.last

      refute actor(raid, 1).alive
    end

    test "a coward leaves a deadly check to the next best one" do
      raid = squad([:pmc, :office], [{:coward, 60}, {:psycho, 40}])
      coward = name(raid, 0)
      other = name(raid, 1)

      assert %{member: ^other, quirk: {:coward, ^coward}} = Raid.choose(raid, 0, 1, :sj6, 1).last
    end

    test "a chatterbox gives the squad away when it hides, and talks scavs round" do
      # the desync's run: an escape (agility -20, a stall at worst), 70% for a plain 50
      raid = squad([:desync, :pmc], [{:chatty, 50}])
      chatty = name(raid, 0)
      assert %{outcome: :pass} = Raid.choose(raid, 1, 60).last

      assert %{outcome: :stall, quirk: {:chatty, ^chatty}} =
               Raid.choose(raid, 1, 60, :sj6, 1).last

      # the toll: a luck check at a scav event, 50%
      raid = squad([:toll, :pmc], [{:chatty, 50}])
      assert %{outcome: :drop} = Raid.choose(raid, 0, 60).last

      assert %{outcome: :pass, quirk: {:chatty_scav, ^chatty}} =
               Raid.choose(raid, 0, 60, :sj6, 1).last
    end

    test "a lucky one's failed check comes off after all" do
      raid = squad([:pmc, :office], [{:lucky, 50}])
      lucky = name(raid, 0)

      assert %{outcome: :pass, quirk: {:lucky, ^lucky}} = Raid.choose(raid, 0, 100, :sj6, 1).last
      # a check that comes off by itself needs no luck
      assert %{outcome: :pass, quirk: nil} = Raid.choose(raid, 0, 10, :sj6, 1).last
      assert %{outcome: :lose} = Raid.choose(raid, 0, 100, :sj6, 26).last
    end
  end
end
