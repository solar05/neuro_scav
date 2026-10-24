defmodule NeuroScav.RaidTest do
  use ExUnit.Case, async: true

  alias NeuroScav.{BattleRoom, Raid}
  alias NeuroScav.Raid.Chart

  @squad [
    %{name: "Алиса Аврора", rarity: :common},
    %{name: "Гена Лена", rarity: :epic},
    %{name: "Дед Мороз", rarity: :legendary}
  ]

  # clear weather from a morning on, unless a test says otherwise: the
  # morning eases a search only, so fights and hiding go as the bare stats
  @calm %{weather: :clear, daytime: :morning}

  defp new_raid(members, map \\ Raid.random_map(), world \\ @calm),
    do: Raid.new(members, map, world)

  defp best(stat), do: @squad |> Enum.map(&Raid.card/1) |> Enum.max_by(& &1.stats[stat])
  defp index_of(card), do: Enum.find_index(@squad, &(&1.name == card.name))

  test "a new raid crosses a map 11 to 14 layers long with the whole squad alive" do
    raid = new_raid(@squad)

    assert Raid.steps() == 11..14
    assert Chart.layers(raid.map) in Raid.steps()
    assert Enum.all?(raid.squad, & &1.alive)
    refute Raid.over?(raid)
  end

  test "a check is made by the member best at its stat, with stat minus difficulty as chance" do
    [fight, climb] = @squad |> new_raid([:pmc]) |> Raid.options()

    assert fight.member.name == best(:strength).name
    assert fight.chance == (best(:strength).stats.strength + 15) |> max(5) |> min(95)
    assert climb.chance == (best(:agility).stats.agility + 10) |> max(5) |> min(95)
  end

  test "a success passes, a failure loses the member who tried" do
    raid = new_raid(@squad, [:pmc, :reshala])
    member = best(:strength).name

    passed = Raid.choose(raid, 0, 1)
    assert %{outcome: :pass, member: ^member} = passed.last
    assert length(Raid.alive(passed)) == 3
    assert Raid.event(passed) == :reshala

    lost = Raid.choose(raid, 0, 100)
    assert %{outcome: :lose, member: ^member} = lost.last
    assert length(Raid.alive(lost)) == 2
    refute Enum.any?(Raid.alive(lost), &(&1.name == member))
  end

  test "loot goes to the stash and adds to later checks" do
    raid = new_raid(@squad, [:office, :pmc])
    raid = Raid.choose(raid, 0, 1, :sj6)

    # the finder is the member who made the check
    assert raid.stash == [%{item: :sj6, owner: best(:strength) |> index_of()}]
    assert %{outcome: :loot, item: :sj6} = raid.last

    [fight, _climb] = Raid.options(raid)
    assert fight.chance == (best(:strength).stats.strength + 10 + 15) |> max(5) |> min(95)
  end

  test "a failed search finds nothing and loses nobody; a safe option risks nothing" do
    raid = new_raid(@squad, [:office, :bait])

    raid = Raid.choose(raid, 0, 100)
    assert %{outcome: :nothing} = raid.last
    assert length(Raid.alive(raid)) == 3

    assert [_get, %{stat: nil}] = Raid.options(raid)
    raid = Raid.choose(raid, 1, 100)
    assert %{outcome: :safe, member: nil} = raid.last
    assert Raid.over?(raid)
  end

  test "the raid is over once nobody is left; members with one name are lost one by one" do
    gnomes = List.duplicate(%{name: "ГНОМ ГНОМЫЧ", rarity: :gnome}, 2)
    raid = new_raid(gnomes, [:pmc, :reshala, :sniper])

    raid = Raid.choose(raid, 0, 100)
    assert length(Raid.alive(raid)) == 1

    raid = Raid.choose(raid, 0, 100)
    assert Raid.over?(raid)
    assert Raid.event(raid) == nil
    # nothing to choose any more
    assert Raid.choose(raid, 0, 1) == raid
  end

  test "chances stay within 5..95" do
    [%{chance: chance} | _] =
      [%{name: "ГНОМ ГНОМЫЧ", rarity: :gnome}] |> new_raid([:bait]) |> Raid.options()

    assert chance == 95
  end

  test "options tell what a success brings and a failure costs" do
    assert [%{reward: :loot, risk: :nothing}, %{stat: nil, reward: nil, risk: nil}] =
             @squad |> new_raid([:office]) |> Raid.options()
  end

  test "a failed drop costs the last item of the stash, not a member" do
    raid = @squad |> new_raid([:office, :office, :toll]) |> Raid.choose(0, 1, :sj6)
    raid = Raid.choose(raid, 0, 1, :rooster)

    raid = Raid.choose(raid, 0, 100)
    assert %{outcome: :drop, item: :rooster} = raid.last
    assert Enum.map(raid.stash, & &1.item) == [:sj6]
    assert length(Raid.alive(raid)) == 3
  end

  test "a check tells its roll and the chance it was against, a safe option neither" do
    raid = new_raid(@squad, [:office, :office])
    [%{chance: chance}, _safe] = Raid.options(raid)

    assert %{roll: 30, chance: ^chance} = Raid.choose(raid, 0, 30, :sj6).last
    assert %{roll: nil, chance: nil} = Raid.choose(raid, 1, 30).last
  end

  test "a check by each tells the roll alone: everyone had their own chance" do
    assert %{roll: 50, chance: nil} = (@squad |> new_raid([:mines]) |> Raid.choose(0, 50)).last
  end

  test "every set the squad collects adds the battle's set bonus to every stat" do
    # Лена and Арена rhyme
    members = [%{name: "Гена Лена", rarity: :epic}, %{name: "Сеня Арена", rarity: :common}]
    raid = new_raid(members)
    assert Raid.sets(raid) == [:rhyme]

    for {member, card} <- Enum.zip(raid.squad, Enum.map(members, &Raid.card/1)),
        {stat, value} <- card.stats,
        do: assert(member.stats[stat] == value + BattleRoom.set_bonus())

    assert Raid.sets(new_raid(@squad)) == []
  end

  test "haggling on the toll path wins the scavs over, talking a driver down trains luck, a train's crate is loot" do
    # failed or not, the scavs take a haggle well
    assert %{outcome: :drop, karma: 1} = (@squad |> new_raid([:toll]) |> Raid.choose(0, 100)).last

    assert %{outcome: :train, stat: :luck} =
             (@squad |> new_raid([:vex]) |> Raid.choose(0, 1)).last

    assert %{outcome: :loot, item: :sj6} =
             (@squad |> new_raid([:train]) |> Raid.choose(0, 1, :sj6)).last
  end

  test "a failed drop with an empty stash costs nothing" do
    raid = @squad |> new_raid([:toll]) |> Raid.choose(0, 100)
    assert %{outcome: :drop, item: nil} = raid.last
    assert raid.stash == []
  end

  test "a revive brings the first fallen member back, with nobody fallen it's a pass" do
    raid = @squad |> new_raid([:pmc, :medic, :medic]) |> Raid.choose(0, 100)
    [fallen] = Enum.reject(raid.squad, & &1.alive)

    raid = Raid.choose(raid, 0, 1)
    assert %{outcome: :revive, member: name} = raid.last
    assert name == fallen.name
    assert length(Raid.alive(raid)) == 3

    raid = Raid.choose(raid, 0, 1)
    assert %{outcome: :pass} = raid.last
  end

  describe "stats and rarity" do
    defp actor(raid, index), do: Enum.at(raid.squad, index)

    test "a raid card cuts the name part of a battle card and keeps the rarity bonus" do
      for member <- @squad, stat <- BattleRoom.stats() do
        battle = BattleRoom.card(member).stats[stat] - BattleRoom.rarity_bonus(member.rarity)
        raid = Raid.card(member).stats[stat] - BattleRoom.rarity_bonus(member.rarity)

        assert raid == max(div(battle * 60, 100), 1)
      end

      gnome = %{name: "Гном", rarity: :gnome}
      assert Raid.card(gnome) == BattleRoom.card(gnome)
    end

    test "a training success raises the checked stat of the member who did it" do
      raid = new_raid(@squad, [:obdolbos])
      [%{member: member}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :train, stat: :luck} = raid.last
      assert actor(raid, member.index).stats.luck == member.stats.luck + Raid.stat_step()
    end

    test "a wound lowers the stat, down to 1 at most, and the member stays" do
      raid = new_raid(@squad, [:obdolbos, :obdolbos])
      [%{member: member}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :wound} = raid.last
      assert actor(raid, member.index).stats.luck == max(member.stats.luck - Raid.stat_step(), 1)
      assert length(Raid.alive(raid)) == 3

      raid = put_in(raid.squad, Enum.map(raid.squad, &put_in(&1.stats.luck, 3)))
      raid = Raid.choose(raid, 0, 100)
      assert Enum.all?(raid.squad, &(&1.stats.luck in [1, 3]))
    end

    test "a promotion lifts the rarity one step and the stats by the bonus difference" do
      raid = new_raid([%{name: "Гена Лена", rarity: :epic}], [:veteran])
      [%{member: before}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      after_ = actor(raid, 0)
      delta = BattleRoom.rarity_bonus(:legendary) - BattleRoom.rarity_bonus(:epic)

      assert %{outcome: :promote} = raid.last
      assert after_.rarity == :legendary
      for stat <- BattleRoom.stats(), do: assert(after_.stats[stat] == before.stats[stat] + delta)
    end

    test "the gnome is off the scale: a promotion trains it, it stays the gnome" do
      raid = new_raid([%{name: "ГНОМ ГНОМЫЧ", rarity: :gnome}], [:veteran])
      [%{member: before}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :train} = raid.last
      assert actor(raid, 0).rarity == :gnome
      assert actor(raid, 0).stats.strength == before.stats.strength + Raid.stat_step()
    end

    test "a legendary has nowhere to go: a promotion trains instead" do
      raid = new_raid([%{name: "Дед Мороз", rarity: :legendary}], [:veteran])
      [%{member: before}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :train} = raid.last
      assert actor(raid, 0).rarity == :legendary
      assert actor(raid, 0).stats.strength == before.stats.strength + Raid.stat_step()
    end

    test "valuable loot turns up more seldom than the rest" do
      finds = for _ <- 1..3_000, do: Raid.random_item()
      count = fn item -> Enum.count(finds, &(&1 == item)) end

      assert MapSet.new(finds) == MapSet.new(Enum.reject(Raid.loot(), &Raid.trophy_item?/1))
      assert count.(:ledx) * 2 < count.(:sj6)
      assert count.(:keycard) * 2 < count.(:bitcoin)
    end

    test "loot is worth its price, a valuable nothing but it; what's carried out adds up" do
      assert Enum.all?(Raid.loot(), &(Raid.price(&1) > 0))
      assert Raid.loot_bonus(:gpu) == %{} and Raid.price(:gpu) > Raid.price(:sj6)
      assert Raid.value([:ledx, :sj6, :sj6]) == Raid.price(:ledx) + 2 * Raid.price(:sj6)
      assert Raid.value([]) == 0
    end

    test "loot may take a stat as well: a heavy helmet slows its finder down" do
      raid = new_raid([%{name: "Дед Мороз", rarity: :legendary}], [:office, :pmc])
      [_fight, climb] = raid |> Raid.choose(0, 1, :sj6) |> Raid.options()
      [_fight, slowed] = raid |> Raid.choose(0, 1, :altyn) |> Raid.options()

      assert slowed.chance == max(climb.chance - 5, 5)
    end

    test "loot bonuses add up for their finder, nothing for the others or the fallen" do
      finder = index_of(best(:strength))
      raid = @squad |> new_raid([:office, :office, :pmc]) |> Raid.choose(0, 1, :sj6)
      raid = Raid.choose(raid, 0, 1, :altyn)

      [owner | others] = Enum.sort_by(raid.squad, &(&1.index != finder))
      assert Raid.loot_bonuses(raid, owner) == %{strength: 20, agility: -5}
      assert Enum.all?(others, &(Raid.loot_bonuses(raid, &1) == %{}))

      raid = Raid.choose(raid, 0, 100)
      assert Raid.loot_bonuses(raid, Enum.at(raid.squad, finder)) == %{}
    end

    test "loot works for its finder alone" do
      finder = best(:strength)
      raid = @squad |> new_raid([:office, :pmc]) |> Raid.choose(0, 1, :meldonin)
      [_fight, climb] = Raid.options(raid)

      best_agility =
        @squad
        |> Enum.map(&Raid.card/1)
        |> Enum.map(&(&1.stats.agility + if(&1.name == finder.name, do: 10, else: 0)))
        |> Enum.max()

      assert climb.chance == (best_agility + 10) |> max(5) |> min(95)
    end

    test "a fallen finder's loot stops working and works again once they're back" do
      finder = best(:strength)

      strongest_other =
        @squad
        |> Enum.map(&Raid.card/1)
        |> Enum.reject(&(&1.name == finder.name))
        |> Enum.max_by(& &1.stats.strength)

      raid = @squad |> new_raid([:office, :pmc, :pmc, :medic, :pmc]) |> Raid.choose(0, 1, :slick)
      assert [%{member: %{name: name}} | _] = Raid.options(raid)
      assert name == finder.name

      # the finder falls: their armor is no use to anyone
      raid = Raid.choose(raid, 0, 100)
      refute Raid.active?(raid, hd(raid.stash))
      [fight, _climb] = Raid.options(raid)
      assert fight.member.name == strongest_other.name
      assert fight.chance == (strongest_other.stats.strength + 15) |> max(5) |> min(95)

      # back on their feet, the armor works again (by now the morning is a day: fights go easier)
      raid = raid |> Raid.choose(0, 1) |> Raid.choose(0, 1)
      assert Raid.active?(raid, hd(raid.stash))
      [fight, _climb] = Raid.options(raid)
      assert fight.member.name == finder.name
      day = Map.get(Raid.world(raid).daytime_kinds, :fight, 0)
      assert fight.chance == (finder.stats.strength + 15 + 15 + day) |> max(5) |> min(95)
    end

    test "a failed drop takes the last active item, not a fallen finder's" do
      raid = new_raid(Enum.take(@squad, 2), [:trunk, :office, :pmc, :toll])
      # one strong, one lucky: each finds an item of their own
      raid =
        update_in(raid.squad, fn [strong, lucky] ->
          [
            %{strong | stats: %{strength: 90, agility: 10, luck: 10}},
            %{lucky | stats: %{strength: 10, agility: 10, luck: 90}}
          ]
        end)

      raid = raid |> Raid.choose(0, 1, :rooster) |> Raid.choose(0, 1, :sj6)
      assert Enum.map(raid.stash, &{&1.item, &1.owner}) == [rooster: 1, sj6: 0]

      raid = raid |> Raid.choose(0, 100) |> Raid.choose(0, 100)
      assert %{outcome: :drop, item: :rooster} = raid.last
      assert Enum.map(raid.stash, & &1.item) == [:sj6]
    end

    test "promoting events come up much more seldom than the others" do
      maps = for _ <- 1..2_000, do: Map.values(Raid.random_map().nodes)
      share = fn event -> Enum.count(maps, &(event in &1)) end

      assert share.(:veteran) * 3 < share.(:pmc)
      assert share.(:lightkeeper) * 3 < share.(:pmc)
    end
  end

  describe "chains and bosses" do
    @chain_events [:reshala_guards, :ambush, :debtor, :drop_hunters, :pmc_killer]

    test "an outcome may bring another event, catching up a few nodes later" do
      raid = @squad |> new_raid([:reshala, :pmc, :office, :medic]) |> Raid.choose(0, 1, :sj6)

      assert %{outcome: :trophy, follow_up: :reshala_guards} = raid.last
      assert Raid.event(raid) == :pmc

      # two nodes later it comes first, the node's own event after it
      raid = Raid.choose(raid, 1, 1)
      assert Raid.event(raid) == :reshala_guards and Raid.at(raid) == {2, 0}
      raid = Raid.choose(raid, 1, 1)
      assert Raid.event(raid) == :office and Raid.at(raid) == {2, 0}
    end

    test "other outcomes of the same event bring nothing" do
      raid = @squad |> new_raid([:reshala, :pmc, :office]) |> Raid.choose(1, 1)

      assert %{outcome: :pass, follow_up: nil} = raid.last
      assert raid.pursuers == []
    end

    test "a chain's event catches up at the last node at the latest; the last starts none" do
      raid = @squad |> new_raid([:bait, :pmc]) |> Raid.choose(1, 1)
      assert Raid.event(raid) == :ambush
      assert raid |> Raid.choose(1, 1, :sj6) |> Raid.event() == :pmc

      raid = @squad |> new_raid([:pmc, :bait]) |> Raid.choose(0, 1) |> Raid.choose(1, 1)
      assert Raid.over?(raid)
      assert %{outcome: :safe, follow_up: nil} = raid.last
    end

    test "beating a boss brings its trophy and a promotion, there is no way around one" do
      raid = new_raid([%{name: "Гена Лена", rarity: :epic}], [:kaban, :pmc])

      assert Enum.all?(Raid.options(raid), & &1.stat)

      raid = Raid.choose(raid, 0, 1, :sj6)
      assert %{outcome: :trophy, item: :pkm} = raid.last
      assert raid.stash == [%{item: :pkm, owner: 0}]
      assert actor(raid, 0).rarity == :legendary
      assert Raid.loot_bonuses(raid, actor(raid, 0)) == Raid.loot_bonus(:pkm)
    end

    test "a legendary beating a boss trains instead, the trophy is theirs all the same" do
      raid = new_raid([%{name: "Дед Мороз", rarity: :legendary}], [:priest])
      [%{member: before}, _escape] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :trophy, item: :amulet} = raid.last
      assert actor(raid, 0).stats.luck == before.stats.luck + Raid.stat_step()
    end

    test "the locations' own bosses fight for a trophy or let the squad go at a wound" do
      for boss <- ~w(reshala shturman sanitar killa glukhar zryachiy tagilla kollontay)a do
        assert Raid.boss?(boss) and Raid.trophy_item?(Raid.trophy(boss))
        options = @squad |> new_raid([boss]) |> Raid.options()

        assert Enum.any?(options, &(&1.reward == :trophy and &1.risk == :lose))
        assert Enum.any?(options, &(&1.reward == :pass and &1.risk == :wound))
      end
    end

    test "Komar's wings are legendary: +40 luck" do
      raid = @squad |> new_raid([:komar]) |> Raid.choose(0, 1)

      assert Raid.boss?(:komar)
      assert %{outcome: :trophy, item: :komar_wings} = raid.last
      assert Raid.loot_bonus(:komar_wings) == %{luck: 40}
      assert Raid.trophy_item?(:komar_wings)
    end

    test "every gnome is after the loot: a failure there may cost an item" do
      for gnome <- [:gnome_thief, :gnome_trader, :gnome_ambush, :gnome_pmc] do
        risks = @squad |> new_raid([gnome]) |> Raid.options() |> Enum.map(& &1.risk)
        assert :drop in risks, "#{gnome}"
      end
    end

    test "the gnome thief steals the last item on a failure, whichever way the squad tries" do
      for index <- [0, 1] do
        raid = @squad |> new_raid([:trunk, :gnome_thief, :pmc]) |> Raid.choose(0, 1, :rooster)
        # no way around but a check, or gold the squad has none of
        assert Enum.all?(Enum.take(Raid.options(raid), 2), & &1.stat)
        assert %{give: :gold_chain, locked: true} = Enum.at(Raid.options(raid), 2)

        raid = Raid.choose(raid, index, 100)
        assert %{event: :gnome_thief, outcome: :drop, item: :rooster} = raid.last
        assert raid.stash == []
      end

      raid = @squad |> new_raid([:gnome_thief]) |> Raid.choose(0, 1, :nvg)
      assert %{outcome: :loot, item: :nvg} = raid.last

      # gold of its own, and the gnome lets the rest be
      raid = @squad |> new_raid([:trunk, :gnome_thief]) |> Raid.choose(0, 1, :gold_chain)
      raid = %{raid | stash: raid.stash ++ [%{item: :rooster, owner: 0}]}
      assert %{outcome: :pass, used: :gold_chain} = Raid.choose(raid, 2, 100).last
      assert Enum.map(Raid.choose(raid, 2, 100).stash, & &1.item) == [:rooster]
    end

    test "random maps hold no chain events and now and then a boss, mid-way or before the exits" do
      maps = for _ <- 1..2_000, do: Raid.random_map()

      bosses =
        for map <- maps,
            {{layer, _column}, event} <- map.nodes,
            Raid.boss?(event),
            do: {Chart.layers(map), layer}

      # @boss_chance 0.8: 1600 expected
      assert length(bosses) in 1450..1750
      for {layers, layer} <- bosses, do: assert(layer in [div(layers, 2), layers - 2])

      refute Enum.any?(maps, fn map ->
               Enum.any?(Map.values(map.nodes), &(&1 in @chain_events))
             end)
    end
  end

  describe "karma" do
    defp luck_chance(route, karma),
      do:
        %{new_raid(@squad, route) | karma: karma} |> Raid.options() |> hd() |> Map.fetch!(:chance)

    test "helping scavs raises it whatever the roll, robbing them lowers it" do
      raid = new_raid(@squad, [:wounded, :scav_camp, :pmc])
      assert raid.karma == 0

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :nothing, karma: 1} = raid.last
      assert raid.karma == 1

      raid = Raid.choose(raid, 1, 1, :sj6)
      assert %{outcome: :loot, karma: -2} = raid.last
      assert raid.karma == -1
    end

    test "going through a sleeping scav's pockets lowers it, caught or not" do
      assert (@squad |> new_raid([:sleeping_scav]) |> Raid.choose(0, 100)).karma == -1
      assert (@squad |> new_raid([:sleeping_scav]) |> Raid.choose(0, 1, :sj6)).karma == -1
    end

    test "it stays within ±3" do
      raid = %{new_raid(@squad, [:wounded]) | karma: 3} |> Raid.choose(0, 1, :sj6)

      assert raid.karma == 3
      assert raid.last.karma == 0
    end

    test "it eases a talk with scavs and nothing else" do
      luck = best(:luck).stats.luck

      assert luck_chance([:toll], 0) == luck |> max(5) |> min(95)
      assert luck_chance([:toll], 2) == (luck + 10) |> max(5) |> min(95)
      assert luck_chance([:toll], -2) == (luck - 10) |> max(5) |> min(95)
      # a sniper is no scav to talk to
      assert luck_chance([:sniper], 3) == luck_chance([:sniper], 0)
    end
  end

  describe "the map" do
    # an office, two ways on from it, both to the car
    @fork %{
      nodes: %{{0, 0} => :office, {1, 0} => :pmc, {1, 1} => :bait, {2, 0} => :exit_car},
      links: %{{0, 0} => [{1, 0}, {1, 1}], {1, 0} => [{2, 0}], {1, 1} => [{2, 0}], {2, 0} => []}
    }

    test "random maps: layers of different events linked forward without crossing, exits last" do
      for _ <- 1..200 do
        map = Raid.random_map()
        layers = Chart.layers(map)
        events = Map.values(map.nodes)

        assert layers in Raid.steps()
        assert events == Enum.uniq(events)

        for {{layer, _column} = id, event} <- map.nodes do
          assert Raid.exit?(event) == (layer == layers - 1)
          assert map.links[id] != [] or layer == layers - 1
          assert Enum.all?(map.links[id], &(elem(&1, 0) == layer + 1))
        end

        # every node past the first layer is reached from one before
        reached = map.links |> Map.values() |> Enum.concat() |> MapSet.new()
        assert Enum.all?(Map.keys(map.nodes), &(elem(&1, 0) == 0 or &1 in reached))

        # two links from one layer keep their order in the next
        links =
          for {{layer, from}, nexts} <- map.links, {_next, to} <- nexts, do: {layer, from, to}

        for {layer, a, b} <- links, {^layer, c, d} <- links, a < c, do: assert(b <= d)
      end
    end

    test "with one node to start the squad is there at once, with more it picks one" do
      raid = new_raid(@squad, [:pmc, :office])
      assert Raid.at(raid) == {0, 0} and Raid.event(raid) == :pmc
      assert Raid.next_nodes(raid) == []

      starts = %{
        nodes: %{{0, 0} => :office, {0, 2} => :pmc, {1, 1} => :bait},
        links: %{{0, 0} => [{1, 1}], {0, 2} => [{1, 1}], {1, 1} => []}
      }

      raid = new_raid(@squad, starts)
      assert Raid.at(raid) == nil and Raid.event(raid) == nil
      refute Raid.over?(raid)
      assert Raid.next_nodes(raid) == [{0, 0}, {0, 2}]
      assert Raid.options(raid) == []

      # a node it can't go to changes nothing, nor does moving while facing an event
      assert Raid.move(raid, {1, 1}) == raid
      raid = Raid.move(raid, {0, 2})
      assert Raid.event(raid) == :pmc
      assert Raid.move(raid, {1, 1}) == raid

      # one way on: the squad goes by itself
      raid = Raid.choose(raid, 0, 1)
      assert Raid.at(raid) == {1, 1} and Raid.event(raid) == :bait
    end

    test "where the way forks the squad picks; through an exit the raid is over" do
      raid = @squad |> new_raid(@fork) |> Raid.choose(1, 1)

      assert Raid.event(raid) == nil
      refute Raid.over?(raid)
      assert Raid.next_nodes(raid) == [{1, 0}, {1, 1}]

      # a move is no choice: the turn and the retreats stay as they were
      raid = Raid.move(raid, {1, 1})
      assert Raid.event(raid) == :bait
      assert raid.turn == 1 and raid.retreats == 1

      raid = Raid.choose(raid, 0, 1, :sj6)
      assert Raid.event(raid) == :exit_car

      raid = Raid.choose(raid, 1, 1)
      assert Raid.over?(raid) and Raid.event(raid) == nil
      assert Raid.at(raid) == {2, 0} and Raid.next_nodes(raid) == []
    end

    test "what the squad has seen it remembers in the dark, by kind" do
      route = [:office, :pmc, :trunk, :bait, :exit_car]

      # seen in the morning, still known at night nine turns on
      raid = new_raid(@squad, route)
      assert Raid.dark?(%{raid | turn: 9})
      assert Raid.sight(%{raid | turn: 9}, {3, 0}) == :remembered

      # a raid starting at night learns it once the morning shows it
      night = new_raid(@squad, route, %{weather: :clear, daytime: :night})
      assert Raid.sight(night, {3, 0}) == :hidden

      raid = Raid.choose(%{night | turn: 2}, 1, 1)
      refute Raid.dark?(raid)
      assert Raid.sight(%{raid | turn: 12}, {3, 0}) == :remembered
    end

    test "what the squad can still get to: forward from where it stands" do
      assert @squad |> new_raid(@fork) |> Raid.reachable() == MapSet.new(Map.keys(@fork.nodes))

      raid = @squad |> new_raid(@fork) |> Raid.choose(1, 1) |> Raid.move({1, 1})
      assert Raid.reachable(raid) == MapSet.new([{1, 1}, {2, 0}])
    end

    test "the squad sees where it's been, where it may go next and the exits; the rest by kind" do
      route = [:office, :pmc, :trunk, :kaban, :exit_car]
      ids = for layer <- 0..4, do: {layer, 0}
      sights = fn world -> Enum.map(ids, &Raid.sight(new_raid(@squad, route, world), &1)) end

      assert sights.(@calm) == [:event, :event, :kind, :kind, :event]
      # at night or in the fog the rest is hidden, a boss aside
      assert sights.(%{weather: :clear, daytime: :night}) == [
               :event,
               :event,
               :hidden,
               :kind,
               :event
             ]

      assert sights.(%{weather: :fog, daytime: :day}) == [:event, :event, :hidden, :kind, :event]

      assert Enum.map(route, &Raid.kind/1) == [:loot, :fight, :loot, :boss, :exit]
      assert Raid.kind(:abandoned_store) == :search and Raid.kind(:toll) == :scav
      assert Raid.kind(:veteran) == :rare and Raid.kind(:gnome_thief) == :gnome
    end
  end

  describe "locations" do
    @locations NeuroScav.Raid.Catalog.compiled().locations

    test "a random map is a location: its exits and its bosses" do
      for location <- Raid.locations(), _ <- 1..30 do
        map = Raid.random_map(location)
        %{exits: exits, bosses: bosses} = @locations[location]
        assert map.location == location

        for event <- Map.values(map.nodes) do
          if Raid.exit?(event), do: assert(event in exits)
          if Raid.boss?(event), do: assert(event in bosses)
        end
      end

      assert Raid.location(new_raid(@squad, Raid.random_map(:woods))) == :woods
      assert Raid.location(new_raid(@squad, [:pmc])) == nil
    end

    test "a location's own events turn up there more often" do
      share = fn location, event ->
        Enum.count(1..400, fn _ -> event in Map.values(Raid.random_map(location).nodes) end)
      end

      assert share.(:customs, :axeman) * 2 > share.(:woods, :axeman) * 3
      assert share.(:woods, :sniper) * 2 > share.(:customs, :sniper) * 3
    end

    test "a location's own boss is met there most, the roaming ones now and then" do
      bosses = fn location ->
        Enum.flat_map(1..400, fn _ ->
          for event <- Map.values(Raid.random_map(location).nodes), Raid.boss?(event), do: event
        end)
        |> Enum.frequencies()
      end

      interchange = bosses.(:interchange)
      assert interchange[:killa] > 2 * interchange[:komar]
      assert interchange[:killa] > 2 * interchange[:kaban]
      refute Map.has_key?(bosses.(:customs), :killa)
    end
  end

  describe "exits" do
    test "the car takes the stash's cheapest active item for sure; with nothing to pay it's locked" do
      raid = new_raid(@squad, [:exit_car])
      assert [%{pay: true, price: nil, locked: true}, _haggle, _walk] = Raid.options(raid)
      assert Raid.choose(raid, 0, 1) == raid

      stash = [%{item: :rooster, owner: 0}, %{item: :sj6, owner: 1}, %{item: :ledx, owner: 0}]
      raid = %{raid | stash: stash}

      assert [%{pay: true, price: :sj6, chance: 100, locked: false} = pay | _] =
               Raid.options(raid)

      assert pay.member.index == 1

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :paid, item: :sj6, index: 1} = raid.last
      assert Enum.map(raid.stash, & &1.item) == [:rooster, :ledx]
      assert Raid.over?(raid)
    end

    test "the co-op exit lets the squad out with the scavs, if they like it" do
      raid = new_raid(@squad, [:exit_coop])
      assert [%{trust: 1, chance: nil, locked: true} | _] = Raid.options(raid)
      assert Raid.choose(raid, 0, 1) == raid

      raid = Raid.choose(%{raid | karma: 1}, 0, 100)
      assert %{outcome: :trusted} = raid.last
      assert Raid.over?(raid)
    end

    test "nothing is locked for running at an exit" do
      raid = %{new_raid(@squad, [:exit_coop]) | retreats: 2}
      assert Enum.map(Raid.options(raid), & &1.locked) == [true, false, false]
    end
  end

  test "a member may be lost where an option can cost one" do
    assert Raid.deadly?(:pmc) and Raid.deadly?(:kaban)
    refute Raid.deadly?(:office) or Raid.deadly?(:trunk)
  end

  test "last always has the same keys, whatever happened" do
    keys =
      Enum.sort(
        ~w(event outcome member index item stat retreat follow_up karma used quirk roll chance)a
      )

    lasts = [
      (@squad |> new_raid([:office]) |> Raid.choose(1, 1)).last,
      (@squad |> new_raid([:office]) |> Raid.choose(0, 1, :sj6)).last,
      (@squad |> new_raid([:kaban]) |> Raid.choose(0, 1)).last,
      (@squad
       |> new_raid([:trunk, :gnome_thief])
       |> Raid.choose(0, 1, :sj6)
       |> Raid.choose(1, 100)).last,
      (@squad |> new_raid([:abandoned_store]) |> Raid.choose(0, 1, :sj6)).last,
      (@squad |> new_raid([:abandoned_store]) |> Raid.choose(1, 1)).last,
      (@squad |> new_raid([:pmc]) |> Raid.choose(0, 100, :sj6, 1)).last
    ]

    for last <- lasts, do: assert(last |> Map.keys() |> Enum.sort() == keys)
  end

  describe "a camp" do
    test "a random map has one, off the first two layers and the one before the exits" do
      for _ <- 1..50 do
        map = Raid.random_map()
        assert [{layer, _column}] = for({id, :camp} <- map.nodes, do: id)
        assert layer in 2..(Chart.layers(map) - 3)
      end
    end

    test "its fire shows in the dark, where the rest ahead is hidden" do
      raid =
        new_raid(@squad, [:office, :office, :camp, :pmc], %{weather: :clear, daytime: :night})

      assert Raid.sight(raid, {2, 0}) == :kind
      assert Raid.sight(raid, {3, 0}) == :hidden
    end

    test "patches up the most wounded, locked with nobody wounded" do
      raid = new_raid(@squad, [:camp, :pmc])

      assert [%{camp: :heal, locked: true}, %{camp: :train}, %{camp: :repack, locked: true}] =
               Raid.options(raid)

      assert Raid.choose(raid, 0, 1) == raid

      raid = put_in(raid.squad, Enum.map(raid.squad, &%{&1 | wounds: &1.index}))
      assert %{member: %{index: 2}, locked: false} = hd(Raid.options(raid))

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :heal, index: 2} = raid.last
      assert Enum.map(raid.squad, & &1.wounds) == [0, 1, 0]
    end

    test "trains the squad's weak spot on the best at it" do
      raid = new_raid(@squad, [:camp, :pmc])

      stats = fn member ->
        %{
          member
          | stats: %{strength: 30 + member.index, agility: 50, luck: 20 + member.index * 5}
        }
      end

      # the best at each: strength 32, agility 50, luck 30 — luck is the weak spot
      raid = put_in(raid.squad, Enum.map(raid.squad, stats))
      assert %{member: %{index: 2}, stat: :luck} = Enum.at(Raid.options(raid), 1)

      raid = Raid.choose(raid, 1, 1)
      assert %{outcome: :train, index: 2, stat: :luck} = raid.last
      assert Enum.at(raid.squad, 2).stats.luck == 30 + Raid.stat_step()
    end

    test "repacks every item to the one best at its stat, a fallen finder's too" do
      raid = new_raid(@squad, [:camp, :pmc])

      stats = fn member ->
        %{
          member
          | stats: %{strength: 10 * (member.index + 1), agility: 50 - 10 * member.index, luck: 30}
        }
      end

      # the second one fallen: the strongest alive is the third, the most agile the first
      squad = raid.squad |> Enum.map(stats) |> List.update_at(1, &%{&1 | alive: false})

      raid = %{
        raid
        | squad: squad,
          stash: [
            %{item: :sj6, owner: 1},
            %{item: :meldonin, owner: 2},
            %{item: :medkit, owner: 1}
          ]
      }

      repacked = Raid.choose(raid, 2, 1)
      assert repacked.last.outcome == :repacked

      # medkit adds nothing: its finder fallen, it goes to the first alive one
      assert repacked.stash == [
               %{item: :sj6, owner: 2},
               %{item: :meldonin, owner: 0},
               %{item: :medkit, owner: 0}
             ]

      # repacked once, nothing would move
      assert Enum.at(Raid.options(%{raid | stash: repacked.stash}), 2).locked
    end

    test "resting is neither a retreat nor a risk" do
      raid = @squad |> new_raid([:office, :camp, :office]) |> Raid.choose(1, 1)
      assert raid.retreats == 1

      raid = Raid.choose(raid, 1, 1)
      assert raid.retreats == 1
      assert Enum.at(Raid.options(raid), 1).locked
    end
  end

  describe "retreats" do
    defp locks(raid), do: raid |> Raid.options() |> Enum.map(& &1.locked)

    test "after a retreat the retreats are locked until the squad takes a risk" do
      assert Raid.retreat_limit() == 1
      raid = new_raid(@squad, [:office, :axeman, :office])

      # the safe option
      raid = Raid.choose(raid, 1, 1)
      assert raid.retreats == 1

      # fists or running from the hatchet: running is a retreat, and it's locked
      assert Enum.map(Raid.options(raid), & &1.retreat) == [false, true]
      assert locks(raid) == [false, true]
      assert Raid.choose(raid, 1, 1) == raid

      raid = Raid.choose(raid, 0, 1, :sj6)
      assert raid.retreats == 0
      assert locks(raid) == [false, false]
    end

    test "an event with nothing but retreats stays open" do
      raid = @squad |> new_raid([:office, :toll]) |> Raid.choose(1, 1)

      assert locks(raid) == [false, false]
    end

    test "leaving a search counts neither way" do
      raid = @squad |> new_raid([:office, :abandoned_store, :pmc]) |> Raid.choose(1, 1)
      raid = Raid.choose(raid, 1, 1)

      assert %{outcome: :left} = raid.last
      assert raid.retreats == 1
    end
  end

  describe "stalls" do
    test "a stall keeps the squad where it is, before a spare event" do
      raid = %{new_raid(@squad, [:desync, :pmc]) | spares: [:office, :bait]}

      # further round the corner fails: the server puts the squad back
      raid = Raid.choose(raid, 1, 100)

      assert %{event: :desync, outcome: :stall} = raid.last
      assert Raid.at(raid) == {0, 0} and raid.turn == 1
      assert raid.map.nodes == %{{0, 0} => :office, {1, 0} => :pmc}
      assert raid.spares == [:bait]
      assert Raid.event(raid) == :office
    end

    test "with no spares left the squad meets the same event again" do
      raid = %{new_raid(@squad, [:desync, :pmc]) | spares: []} |> Raid.choose(1, 100)

      assert Raid.at(raid) == {0, 0} and raid.turn == 1
      assert Raid.event(raid) == :desync
    end

    test "spares are off the map and don't stall themselves" do
      for _ <- 1..50 do
        raid = new_raid(@squad)
        taken = Map.values(raid.map.nodes)

        assert length(raid.spares) == 5

        for spare <- raid.spares do
          refute spare in taken
          refute Enum.any?(@squad |> new_raid([spare]) |> Raid.options(), &(&1.risk == :stall))
        end
      end
    end
  end
end
