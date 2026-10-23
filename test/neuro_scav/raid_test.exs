defmodule NeuroScav.RaidTest do
  use ExUnit.Case, async: true

  alias NeuroScav.{BattleRoom, Raid}

  @squad [
    %{name: "Алиса Аврора", rarity: :common},
    %{name: "Гена Лена", rarity: :epic},
    %{name: "Дед Мороз", rarity: :legendary}
  ]

  defp best(stat), do: @squad |> Enum.map(&Raid.card/1) |> Enum.max_by(& &1.stats[stat])
  defp index_of(card), do: Enum.find_index(@squad, &(&1.name == card.name))

  test "a new raid walks 10 to 13 different events with the whole squad alive" do
    raid = Raid.new(@squad)

    assert Raid.steps() == 10..13
    assert length(raid.route) in Raid.steps()
    assert raid.route == Enum.uniq(raid.route)
    assert Enum.all?(raid.squad, & &1.alive)
    refute Raid.over?(raid)
  end

  test "a check is made by the member best at its stat, with stat minus difficulty as chance" do
    [fight, climb] = @squad |> Raid.new([:pmc]) |> Raid.options()

    assert fight.member.name == best(:strength).name
    assert fight.chance == best(:strength).stats.strength |> max(5) |> min(95)
    assert climb.chance == (best(:agility).stats.agility - 10) |> max(5) |> min(95)
  end

  test "a success passes, a failure loses the member who tried" do
    raid = Raid.new(@squad, [:pmc, :reshala])
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
    raid = Raid.new(@squad, [:office, :pmc])
    raid = Raid.choose(raid, 0, 1, :sj6)

    # the finder is the member who made the check
    assert raid.stash == [%{item: :sj6, owner: best(:strength) |> index_of()}]
    assert %{outcome: :loot, item: :sj6} = raid.last

    [fight, _climb] = Raid.options(raid)
    assert fight.chance == (best(:strength).stats.strength + 10) |> max(5) |> min(95)
  end

  test "a failed search finds nothing and loses nobody; a safe option risks nothing" do
    raid = Raid.new(@squad, [:office, :bait])

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
    raid = Raid.new(gnomes, [:pmc, :reshala, :sniper])

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
      [%{name: "ГНОМ ГНОМЫЧ", rarity: :gnome}] |> Raid.new([:bait]) |> Raid.options()

    assert chance == 95
  end

  test "options tell what a success brings and a failure costs" do
    assert [%{reward: :loot, risk: :nothing}, %{stat: nil, reward: nil, risk: nil}] =
             @squad |> Raid.new([:office]) |> Raid.options()
  end

  test "a failed drop costs the last item of the stash, not a member" do
    raid = @squad |> Raid.new([:office, :office, :toll]) |> Raid.choose(0, 1, :sj6)
    raid = Raid.choose(raid, 0, 1, :rooster)

    raid = Raid.choose(raid, 0, 100)
    assert %{outcome: :drop, item: :rooster} = raid.last
    assert Enum.map(raid.stash, & &1.item) == [:sj6]
    assert length(Raid.alive(raid)) == 3
  end

  test "a failed drop with an empty stash costs nothing" do
    raid = @squad |> Raid.new([:toll]) |> Raid.choose(0, 100)
    assert %{outcome: :drop, item: nil} = raid.last
    assert raid.stash == []
  end

  test "a revive brings the first fallen member back, with nobody fallen it's a pass" do
    raid = @squad |> Raid.new([:pmc, :medic, :medic]) |> Raid.choose(0, 100)
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
      raid = Raid.new(@squad, [:obdolbos])
      [%{member: member}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :train, stat: :luck} = raid.last
      assert actor(raid, member.index).stats.luck == member.stats.luck + Raid.stat_step()
    end

    test "a wound lowers the stat, down to 1 at most, and the member stays" do
      raid = Raid.new(@squad, [:obdolbos, :obdolbos])
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
      raid = Raid.new([%{name: "Гена Лена", rarity: :epic}], [:veteran])
      [%{member: before}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      after_ = actor(raid, 0)
      delta = BattleRoom.rarity_bonus(:legendary) - BattleRoom.rarity_bonus(:epic)

      assert %{outcome: :promote} = raid.last
      assert after_.rarity == :legendary
      for stat <- BattleRoom.stats(), do: assert(after_.stats[stat] == before.stats[stat] + delta)
    end

    test "the gnome is off the scale: a promotion trains it, it stays the gnome" do
      raid = Raid.new([%{name: "ГНОМ ГНОМЫЧ", rarity: :gnome}], [:veteran])
      [%{member: before}, _safe] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :train} = raid.last
      assert actor(raid, 0).rarity == :gnome
      assert actor(raid, 0).stats.strength == before.stats.strength + Raid.stat_step()
    end

    test "a legendary has nowhere to go: a promotion trains instead" do
      raid = Raid.new([%{name: "Дед Мороз", rarity: :legendary}], [:veteran])
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

    test "loot may take a stat as well: a heavy helmet slows its finder down" do
      raid = Raid.new([%{name: "Дед Мороз", rarity: :legendary}], [:office, :pmc])
      [_fight, climb] = raid |> Raid.choose(0, 1, :sj6) |> Raid.options()
      [_fight, slowed] = raid |> Raid.choose(0, 1, :altyn) |> Raid.options()

      assert slowed.chance == max(climb.chance - 5, 5)
    end

    test "loot bonuses add up for their finder, nothing for the others or the fallen" do
      finder = index_of(best(:strength))
      raid = @squad |> Raid.new([:office, :office, :pmc]) |> Raid.choose(0, 1, :sj6)
      raid = Raid.choose(raid, 0, 1, :altyn)

      [owner | others] = Enum.sort_by(raid.squad, &(&1.index != finder))
      assert Raid.loot_bonuses(raid, owner) == %{strength: 20, agility: -5}
      assert Enum.all?(others, &(Raid.loot_bonuses(raid, &1) == %{}))

      raid = Raid.choose(raid, 0, 100)
      assert Raid.loot_bonuses(raid, Enum.at(raid.squad, finder)) == %{}
    end

    test "loot works for its finder alone" do
      finder = best(:strength)
      raid = @squad |> Raid.new([:office, :pmc]) |> Raid.choose(0, 1, :meldonin)
      [_fight, climb] = Raid.options(raid)

      best_agility =
        @squad
        |> Enum.map(&Raid.card/1)
        |> Enum.map(&(&1.stats.agility + if(&1.name == finder.name, do: 10, else: 0)))
        |> Enum.max()

      assert climb.chance == (best_agility - 10) |> max(5) |> min(95)
    end

    test "a fallen finder's loot stops working and works again once they're back" do
      finder = best(:strength)

      strongest_other =
        @squad
        |> Enum.map(&Raid.card/1)
        |> Enum.reject(&(&1.name == finder.name))
        |> Enum.max_by(& &1.stats.strength)

      raid = @squad |> Raid.new([:office, :pmc, :pmc, :medic, :pmc]) |> Raid.choose(0, 1, :slick)
      assert [%{member: %{name: name}} | _] = Raid.options(raid)
      assert name == finder.name

      # the finder falls: their armor is no use to anyone
      raid = Raid.choose(raid, 0, 100)
      refute Raid.active?(raid, hd(raid.stash))
      [fight, _climb] = Raid.options(raid)
      assert fight.member.name == strongest_other.name
      assert fight.chance == strongest_other.stats.strength |> max(5) |> min(95)

      # back on their feet, the armor works again
      raid = raid |> Raid.choose(0, 1) |> Raid.choose(0, 1)
      assert Raid.active?(raid, hd(raid.stash))
      [fight, _climb] = Raid.options(raid)
      assert fight.member.name == finder.name
      assert fight.chance == (finder.stats.strength + 15) |> max(5) |> min(95)
    end

    test "a failed drop takes the last active item, not a fallen finder's" do
      raid = Raid.new(Enum.take(@squad, 2), [:trunk, :office, :pmc, :toll])
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
      routes = for _ <- 1..2_000, do: Raid.route()
      share = fn event -> Enum.count(routes, &(event in &1)) end

      assert share.(:veteran) * 3 < share.(:pmc)
      assert share.(:lightkeeper) * 3 < share.(:pmc)
      assert Enum.all?(routes, &(length(&1) in Raid.steps() and &1 == Enum.uniq(&1)))
    end
  end

  describe "chains and bosses" do
    @chain_events [:reshala_guards, :ambush, :debtor, :drop_hunters, :pmc_killer]

    test "an outcome may bring another event a few events later" do
      raid = @squad |> Raid.new([:reshala, :pmc, :office, :medic]) |> Raid.choose(0, 1, :sj6)

      assert %{outcome: :loot, follow_up: :reshala_guards} = raid.last
      assert raid.route == [:reshala, :pmc, :reshala_guards, :office, :medic]
    end

    test "other outcomes of the same event bring nothing" do
      raid = @squad |> Raid.new([:reshala, :pmc, :office]) |> Raid.choose(1, 1)

      assert %{outcome: :pass, follow_up: nil} = raid.last
      assert raid.route == [:reshala, :pmc, :office]
    end

    test "a chain's event comes before the last one at the latest; the last starts none" do
      raid = @squad |> Raid.new([:bait, :pmc]) |> Raid.choose(1, 1)
      assert raid.route == [:bait, :ambush, :pmc]

      raid = @squad |> Raid.new([:pmc, :bait]) |> Raid.choose(0, 1) |> Raid.choose(1, 1)
      assert Raid.over?(raid)
      assert %{outcome: :safe, follow_up: nil} = raid.last
      assert raid.route == [:pmc, :bait]
    end

    test "beating a boss brings its trophy and a promotion, there is no way around one" do
      raid = Raid.new([%{name: "Гена Лена", rarity: :epic}], [:kaban, :pmc])

      assert Enum.all?(Raid.options(raid), & &1.stat)

      raid = Raid.choose(raid, 0, 1, :sj6)
      assert %{outcome: :trophy, item: :pkm} = raid.last
      assert raid.stash == [%{item: :pkm, owner: 0}]
      assert actor(raid, 0).rarity == :legendary
      assert Raid.loot_bonuses(raid, actor(raid, 0)) == Raid.loot_bonus(:pkm)
    end

    test "a legendary beating a boss trains instead, the trophy is theirs all the same" do
      raid = Raid.new([%{name: "Дед Мороз", rarity: :legendary}], [:priest])
      [%{member: before}, _escape] = Raid.options(raid)

      raid = Raid.choose(raid, 0, 1)
      assert %{outcome: :trophy, item: :amulet} = raid.last
      assert actor(raid, 0).stats.luck == before.stats.luck + Raid.stat_step()
    end

    test "Komar's wings are legendary: +40 luck" do
      raid = @squad |> Raid.new([:komar]) |> Raid.choose(0, 1)

      assert Raid.boss?(:komar)
      assert %{outcome: :trophy, item: :komar_wings} = raid.last
      assert Raid.loot_bonus(:komar_wings) == %{luck: 40}
      assert Raid.trophy_item?(:komar_wings)
    end

    test "every gnome is after the loot: a failure there may cost an item" do
      for gnome <- [:gnome_thief, :gnome_trader, :gnome_ambush, :gnome_pmc] do
        risks = @squad |> Raid.new([gnome]) |> Raid.options() |> Enum.map(& &1.risk)
        assert :drop in risks, "#{gnome}"
      end
    end

    test "the gnome thief steals the last item on a failure, whichever way the squad tries" do
      for index <- [0, 1] do
        raid = @squad |> Raid.new([:trunk, :gnome_thief, :pmc]) |> Raid.choose(0, 1, :rooster)
        assert Enum.all?(Raid.options(raid), & &1.stat)

        raid = Raid.choose(raid, index, 100)
        assert %{event: :gnome_thief, outcome: :drop, item: :rooster} = raid.last
        assert raid.stash == []
      end

      raid = @squad |> Raid.new([:gnome_thief]) |> Raid.choose(0, 1, :nvg)
      assert %{outcome: :loot, item: :nvg} = raid.last
    end

    test "random routes hold no chain events and now and then a boss, in the middle or at the end" do
      routes = for _ <- 1..2_000, do: Raid.route()

      bosses =
        for route <- routes,
            {event, at} <- Enum.with_index(route),
            Raid.boss?(event),
            do: {route, at}

      # @boss_chance 0.4: 800 expected
      assert length(bosses) in 650..950

      for {route, at} <- bosses,
          do: assert(at in [div(length(route), 2), length(route) - 1])

      refute Enum.any?(routes, fn route -> Enum.any?(route, &(&1 in @chain_events)) end)
    end
  end

  describe "karma" do
    defp luck_chance(route, karma),
      do:
        %{Raid.new(@squad, route) | karma: karma} |> Raid.options() |> hd() |> Map.fetch!(:chance)

    test "helping scavs raises it whatever the roll, robbing them lowers it" do
      raid = Raid.new(@squad, [:wounded, :scav_camp, :pmc])
      assert raid.karma == 0

      raid = Raid.choose(raid, 0, 100)
      assert %{outcome: :nothing, karma: 1} = raid.last
      assert raid.karma == 1

      raid = Raid.choose(raid, 1, 1, :sj6)
      assert %{outcome: :loot, karma: -2} = raid.last
      assert raid.karma == -1
    end

    test "going through a sleeping scav's pockets lowers it, caught or not" do
      assert (@squad |> Raid.new([:sleeping_scav]) |> Raid.choose(0, 100)).karma == -1
      assert (@squad |> Raid.new([:sleeping_scav]) |> Raid.choose(0, 1, :sj6)).karma == -1
    end

    test "it stays within ±3" do
      raid = %{Raid.new(@squad, [:wounded]) | karma: 3} |> Raid.choose(0, 1, :sj6)

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

  describe "crossroads" do
    test "a path that isn't there changes nothing" do
      raid = Raid.new(@squad, [:fork_road, :pmc], %{fork_road: [:office, :bait]})

      assert Raid.choose(raid, 2, 1) == raid
    end

    test "its paths may be pinned when the raid starts" do
      raid = Raid.new(@squad, [:fork_road, :pmc], %{fork_road: [:office, :bait]})

      assert Enum.map(Raid.options(raid), & &1.path) == [:office, :bait]
      assert raid |> Raid.choose(1, 100) |> Raid.event() == :bait
    end

    test "it offers two paths off the route; the one taken comes next" do
      raid = Raid.new(@squad, [:fork_road, :pmc, :office])
      %{fork_road: [first, second] = paths} = raid.forks

      assert first != second

      for path <- paths,
          do: refute(path in raid.route or Raid.boss?(path) or Raid.crossroads?(path))

      assert Enum.map(Raid.options(raid), &{&1.stat, &1.path}) == [{nil, first}, {nil, second}]

      raid = Raid.choose(raid, 1, 100)
      assert %{outcome: :path, path: ^second} = raid.last
      assert raid.route == [:fork_road, second, :pmc, :office]
      assert Raid.event(raid) == second
    end

    test "two crossroads never offer the same path, the last one still leads somewhere" do
      for _ <- 1..50 do
        raid = Raid.new(@squad, [:radio, :fork_tunnel])
        assert raid.forks.radio -- raid.forks.fork_tunnel == raid.forks.radio
      end

      raid = Raid.new(@squad, [:radio])
      [path, _other] = raid.forks.radio

      raid = Raid.choose(raid, 0, 100)
      refute Raid.over?(raid)
      assert Raid.event(raid) == path
    end
  end

  test "last always has the same keys, whatever happened" do
    keys = Enum.sort(~w(event outcome member index item stat path retreat follow_up karma)a)

    lasts = [
      (@squad |> Raid.new([:office]) |> Raid.choose(1, 1)).last,
      (@squad |> Raid.new([:office]) |> Raid.choose(0, 1, :sj6)).last,
      (@squad |> Raid.new([:fork_road, :pmc]) |> Raid.choose(0, 1)).last,
      (@squad |> Raid.new([:kaban]) |> Raid.choose(0, 1)).last,
      (@squad
       |> Raid.new([:trunk, :gnome_thief])
       |> Raid.choose(0, 1, :sj6)
       |> Raid.choose(1, 100)).last
    ]

    for last <- lasts, do: assert(last |> Map.keys() |> Enum.sort() == keys)
  end

  describe "retreats" do
    defp locks(raid), do: raid |> Raid.options() |> Enum.map(& &1.locked)

    test "after two in a row the retreats are locked until the squad takes a risk" do
      assert Raid.retreat_limit() == 2
      raid = Raid.new(@squad, [:office, :office, :axeman, :office])

      # the safe option twice
      raid = raid |> Raid.choose(1, 1) |> Raid.choose(1, 1)
      assert raid.retreats == 2

      # fists or running from the hatchet: running is a retreat, and it's locked
      assert Enum.map(Raid.options(raid), & &1.retreat) == [false, true]
      assert locks(raid) == [false, true]
      assert Raid.choose(raid, 1, 1) == raid

      raid = Raid.choose(raid, 0, 1, :sj6)
      assert raid.retreats == 0
      assert locks(raid) == [false, false]
    end

    test "an event with nothing but retreats stays open" do
      raid =
        @squad |> Raid.new([:office, :office, :toll]) |> Raid.choose(1, 1) |> Raid.choose(1, 1)

      assert locks(raid) == [false, false]
    end

    test "a crossroads path counts neither way" do
      raid = @squad |> Raid.new([:office, :fork_road, :pmc]) |> Raid.choose(1, 1)
      raid = Raid.choose(raid, 0, 1)

      assert %{outcome: :path} = raid.last
      assert raid.retreats == 1
    end
  end

  describe "stalls" do
    test "a stall keeps the squad where it is, before a spare event" do
      raid = %{Raid.new(@squad, [:desync, :pmc]) | spares: [:office, :bait]}

      # further round the corner fails: the server puts the squad back
      raid = Raid.choose(raid, 1, 100)

      assert %{event: :desync, outcome: :stall} = raid.last
      assert raid.step == 0 and raid.turn == 1
      assert raid.route == [:office, :pmc]
      assert raid.spares == [:bait]
      assert Raid.event(raid) == :office
    end

    test "with no spares left the squad meets the same event again" do
      raid = %{Raid.new(@squad, [:desync, :pmc]) | spares: []} |> Raid.choose(1, 100)

      assert raid.step == 0 and raid.turn == 1
      assert Raid.event(raid) == :desync
    end

    test "spares are off the route and the crossroads paths, and don't stall themselves" do
      for _ <- 1..50 do
        raid = Raid.new(@squad, [:fork_road, :pmc, :desync])
        taken = raid.route ++ raid.forks.fork_road

        assert length(raid.spares) == 5

        for spare <- raid.spares do
          refute spare in taken
          refute Enum.any?(@squad |> Raid.new([spare]) |> Raid.options(), &(&1.risk == :stall))
        end
      end
    end
  end
end
