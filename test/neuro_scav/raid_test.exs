defmodule NeuroScav.RaidTest do
  use ExUnit.Case, async: true

  alias NeuroScav.{BattleRoom, Raid}

  @squad [
    %{name: "Алиса Аврора", rarity: :common},
    %{name: "Гена Лена", rarity: :epic},
    %{name: "Дед Мороз", rarity: :legendary}
  ]

  defp best(stat), do: @squad |> Enum.map(&BattleRoom.card/1) |> Enum.max_by(& &1.stats[stat])
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

      assert MapSet.new(finds) == MapSet.new(Raid.loot())
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
        |> Enum.map(&BattleRoom.card/1)
        |> Enum.map(&(&1.stats.agility + if(&1.name == finder.name, do: 10, else: 0)))
        |> Enum.max()

      assert climb.chance == (best_agility - 10) |> max(5) |> min(95)
    end

    test "a fallen finder's loot stops working and works again once they're back" do
      finder = best(:strength)

      strongest_other =
        @squad
        |> Enum.map(&BattleRoom.card/1)
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
      raid = Raid.new(Enum.take(@squad, 2), [:wounded, :office, :pmc, :toll])
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
end
