defmodule NeuroScav.Raid do
  @moduledoc """
  A raid, Tarkov style: a short text roguelike for a squad of scavs.

  The squad meets a number of events (`steps/0`, picked per raid) one by one.
  Each event offers two or three options; an option either needs a stat check or is safe (nothing happens).
  A check is made by the alive member best at that stat counting their own
  loot: the chance is the stat (`card/1`, a lowered battle card) plus the
  bonuses of the loot that member found, minus the option's difficulty, kept
  within 5..95%. Loot helps its finder only, and only while they're alive: a
  fallen member's loot stays in the stash, inactive, and works again if they
  come back. What a success brings and a failure costs depends on the option:

  - success: `:pass`, `:loot` (an item to the stash, `%{item, owner}` with
    the finder's index), `:revive` (the first
    fallen member is back; with nobody fallen it's a pass), `:train` (the
    member's checked stat grows by `stat_step/0`), `:promote` (the member's
    rarity goes one up, the stats grow by the difference of rarity bonuses;
    at the top it's a `:train`) or `:trophy` (a won boss fight: the boss's
    own loot, `trophy/1`, and a promotion, a training at the top)
  - failure: `:lose` (the member doesn't make it out), `:wound` (the checked
    stat drops by `stat_step/0`, to 1 at least), `:drop` (the last active
    item of the stash is gone) or `:nothing`

  Routes pick events by weight: the promoting ones are rare. A route may get
  a boss (`boss?/1`), in the middle or at the end; beating one brings a trophy.

  Some outcomes start a chain: another event (never on a random route) comes
  a few events later, before the last one, so the route grows by one. What
  brought it is in `last.follow_up`.

  At a crossroads (`crossroads?/1`) there's no check: each option is a path,
  an event drawn when the raid starts (`forks`), and the one taken comes next.

  Scavs remember: some options change the squad's `karma` (within
  ±`@karma_limit`, the change is in `last.karma`), and every point of it
  eases a luck check at a scav event by `@karma_step`, a bad one makes it harder.

  A raid is plain data: the page keeps it, every step returns a new one. The
  roll (1..100) and the loot found are arguments, so a raid is fully
  predictable in tests.
  """

  alias NeuroScav.BattleRoom

  # option: {stat, difficulty, on success, on failure} or :safe
  @events %{
    pmc: [{:strength, 0, :pass, :lose}, {:agility, 10, :pass, :lose}],
    reshala: [{:strength, 15, :loot, :lose}, {:agility, 5, :pass, :lose}],
    sniper: [{:agility, 0, :pass, :lose}, {:luck, -10, :pass, :lose}],
    mines: [{:agility, 0, :pass, :lose}, {:luck, 10, :pass, :lose}],
    office: [{:strength, 10, :loot, :nothing}, :safe],
    bait: [{:agility, 15, :loot, :lose}, :safe],
    killa: [{:strength, 15, :loot, :lose}, {:luck, 5, :pass, :lose}],
    wounded: [{:luck, 0, :loot, :nothing}, :safe],
    tagilla: [{:strength, 20, :loot, :lose}, {:agility, 5, :pass, :lose}],
    shturman: [{:agility, 10, :loot, :lose}, {:luck, 0, :pass, :lose}],
    cultists: [{:agility, 5, :pass, :lose}, {:luck, 10, :pass, :lose}],
    raiders: [{:strength, 20, :loot, :lose}, {:agility, 10, :pass, :lose}],
    toll: [{:luck, 0, :pass, :drop}, :safe],
    airdrop: [{:agility, 20, :loot, :lose}, :safe],
    medic: [{:luck, 0, :revive, :nothing}, :safe],
    bridge: [{:agility, 10, :pass, :lose}, {:luck, 5, :pass, :drop}],
    sanitar: [
      {:strength, 20, :loot, :lose},
      {:luck, 10, :revive, :drop},
      {:agility, 5, :pass, :lose}
    ],
    glukhar: [{:strength, 25, :loot, :lose}, {:agility, 10, :pass, :lose}],
    kollontay: [{:luck, 5, :pass, :drop}, {:strength, 15, :loot, :lose}],
    zryachiy: [{:agility, 15, :pass, :lose}, :safe],
    vex: [{:luck, 0, :pass, :drop}, :safe],
    tripwire: [{:agility, -5, :pass, :lose}, {:luck, 10, :loot, :lose}],
    dead_pmc: [{:luck, 5, :loot, :lose}, :safe],
    labs: [{:strength, 25, :loot, :lose}, {:agility, 20, :loot, :lose}, :safe],
    obdolbos: [{:luck, 0, :train, :wound}, :safe],
    skirmish: [{:strength, 5, :train, :wound}, {:agility, 0, :pass, :lose}],
    stairs: [{:agility, 10, :train, :wound}, :safe],
    veteran: [{:strength, 20, :promote, :wound}, :safe],
    lightkeeper: [{:agility, 25, :promote, :lose}, :safe],
    rogues: [{:agility, 20, :loot, :lose}, {:luck, 10, :pass, :drop}],
    bunker: [{:luck, 5, :loot, :lose}, :safe],
    mechanic: [{:agility, 10, :loot, :lose}, :safe],
    train: [{:agility, 5, :pass, :lose}, :safe],
    trunk: [{:luck, 0, :loot, :wound}, :safe],
    goons: [{:strength, 30, :loot, :lose}, {:agility, 10, :pass, :lose}, :safe],
    flea: [{:luck, 0, :loot, :drop}, :safe],
    tower: [{:agility, 5, :train, :lose}, :safe],
    # chains, see @chains
    reshala_guards: [{:strength, 20, :loot, :lose}, {:agility, 10, :pass, :wound}],
    ambush: [{:agility, 10, :pass, :wound}, {:strength, 15, :loot, :lose}],
    debtor: [{:luck, -15, :revive, :nothing}, :safe],
    drop_hunters: [{:agility, 15, :pass, :drop}, {:strength, 20, :loot, :lose}],
    pmc_killer: [{:strength, 15, :loot, :lose}, {:luck, 10, :pass, :drop}],
    # bosses: no way around, only a fight for the trophy or a costly escape
    kaban: [{:strength, 30, :trophy, :lose}, {:agility, 15, :pass, :wound}],
    partisan: [{:agility, 30, :trophy, :lose}, {:luck, 15, :pass, :wound}],
    priest: [{:luck, 30, :trophy, :lose}, {:agility, 15, :pass, :wound}],
    # the toughest: its trophy is legendary
    komar: [{:agility, 35, :trophy, :lose}, {:luck, 15, :pass, :wound}],
    # a thief: whatever the squad tries, a failure costs loot
    gnome_thief: [{:agility, 10, :loot, :drop}, {:luck, 5, :pass, :drop}],
    # scavs, see @karma
    scav_camp: [{:luck, 5, :loot, :nothing}, {:strength, 10, :loot, :lose}, :safe],
    fence: [{:luck, 15, :loot, :nothing}, :safe],
    scav_patrol: [{:luck, 10, :pass, :wound}, {:strength, 15, :loot, :lose}],
    lost_scav: [{:agility, 10, :train, :wound}, :safe],
    # Tarkov as players know it
    hatchling: [{:strength, 0, :loot, :wound}, {:agility, 10, :pass, :drop}],
    cheater: [{:luck, 25, :loot, :lose}, {:agility, 10, :pass, :wound}],
    desync: [{:luck, 10, :pass, :lose}, {:agility, 0, :pass, :wound}],
    extract_campers: [{:agility, 15, :pass, :lose}, {:luck, 10, :pass, :drop}],
    prapor_quest: [{:luck, 5, :train, :nothing}, :safe],
    sleeping_scav: [{:agility, 5, :loot, :wound}, :safe],
    streets_fps: [{:agility, 15, :pass, :wound}, {:luck, 5, :train, :nothing}],
    bear_usec: [{:luck, 5, :loot, :nothing}, {:agility, 10, :pass, :lose}],
    grenade_scav: [{:agility, 0, :loot, :wound}, {:luck, 10, :pass, :wound}],
    door_key: [{:strength, 10, :loot, :wound}, {:luck, 20, :loot, :nothing}]
  }

  # crossroads: no options of their own, see `forks` in new/2
  @crossroads [:fork_road, :fork_tunnel, :radio]

  # how often an event comes up on a route, 1 unless listed
  @weights %{
    veteran: 0.12,
    lightkeeper: 0.12,
    fork_road: 0.5,
    fork_tunnel: 0.5,
    radio: 0.5,
    gnome_thief: 0.5
  }

  @bosses [:kaban, :partisan, :priest, :komar]
  @boss_chance 0.4
  # a boss's own loot: nothing else brings it
  @trophies %{kaban: :pkm, partisan: :ghillie, priest: :amulet, komar: :komar_wings}

  # {event, the stat checked} => how the scavs take it
  @karma %{
    {:wounded, :luck} => 1,
    {:lost_scav, :agility} => 1,
    {:scav_camp, :luck} => 1,
    {:scav_camp, :strength} => -2,
    {:scav_patrol, :strength} => -1,
    {:reshala, :strength} => -1,
    {:reshala_guards, :strength} => -1,
    {:sleeping_scav, :agility} => -1
  }
  @karma_limit 3
  @karma_step 5
  # where karma counts: the luck checks here are talks with scavs
  @scav_events [:toll, :flea, :medic, :wounded, :debtor, :scav_camp, :fence, :scav_patrol]

  # {event, outcome} => {the event it brings, how many events later}
  @chains %{
    {:reshala, :loot} => {:reshala_guards, 2},
    {:bait, :safe} => {:ambush, 2},
    {:wounded, :loot} => {:debtor, 3},
    {:airdrop, :loot} => {:drop_hunters, 1},
    {:dead_pmc, :loot} => {:pmc_killer, 2}
  }
  @follow_ups for {_trigger, {event, _delay}} <- @chains, do: event
  # what a random route or a crossroads path is drawn from
  @common Map.keys(@events) -- (@bosses ++ @follow_ups)

  @rarities [:common, :uncommon, :rare, :epic, :legendary]
  @stat_step 10
  # the share (%) of a battle card's name part a raid stat keeps: with whole
  # cards the best of five passes nearly every check
  @base_share 70

  # loot: the stats it adds to every check of the squad (some take a little too)
  @loot %{
    sj6: %{strength: 10},
    meldonin: %{agility: 10},
    rooster: %{luck: 10},
    ledx: %{strength: 5, agility: 5, luck: 5},
    propital: %{strength: 5, agility: 5},
    etg: %{agility: 15, luck: -5},
    slick: %{strength: 15},
    altyn: %{strength: 10, agility: -5},
    moonshine: %{strength: 10, luck: -5},
    bitcoin: %{luck: 5},
    keycard: %{luck: 15},
    nvg: %{agility: 5, luck: 5},
    # trophies, see @trophies
    pkm: %{strength: 20},
    ghillie: %{agility: 15, luck: 5},
    amulet: %{luck: 20},
    komar_wings: %{luck: 40}
  }

  # how often a kind of loot turns up, 1 unless listed: the valuables are rare
  @loot_weights %{ledx: 0.3, keycard: 0.3, slick: 0.5}

  @steps 10..13

  @doc "How many events a raid goes through, picked for each raid."
  @spec steps() :: Range.t()
  def steps, do: @steps

  @doc "Every event."
  @spec events() :: [atom()]
  def events, do: Map.keys(@events) ++ @crossroads

  @doc "How much a member's stat grows or drops on `:train` and `:wound`."
  @spec stat_step() :: pos_integer()
  def stat_step, do: @stat_step

  @doc "Whether an event is a boss."
  @spec boss?(atom()) :: boolean()
  def boss?(event), do: event in @bosses

  @doc "Whether an event is a crossroads: its options are paths."
  @spec crossroads?(atom()) :: boolean()
  def crossroads?(event), do: event in @crossroads

  @doc "The loot beating a boss brings, nil for any other event."
  @spec trophy(atom()) :: atom() | nil
  def trophy(event), do: @trophies[event]

  @doc "Whether a piece of loot is a boss's trophy."
  @spec trophy_item?(atom()) :: boolean()
  def trophy_item?(item), do: item in Map.values(@trophies)

  @doc """
  A random route: as many different events as `steps/0` picks, drawn by
  weight (keys `u^(1/weight)`, the largest win), so rare events seldom show up.
  Bosses and chain events aren't drawn: with `@boss_chance` a boss takes the
  middle or the last place.
  """
  @spec route() :: [atom()]
  def route do
    route = draw(@common ++ @crossroads, @weights, Enum.random(@steps))

    if :rand.uniform() < @boss_chance do
      List.replace_at(route, Enum.random([div(length(route), 2), -1]), Enum.random(@bosses))
    else
      route
    end
  end

  @doc "A random find, drawn by weight like a route: the valuables are rare, trophies never."
  @spec random_item() :: atom()
  def random_item, do: hd(draw(Enum.reject(loot(), &trophy_item?/1), @loot_weights, 1))

  # `count` different keys, each with a chance by its weight (1 unless listed)
  defp draw(keys, weights, count) do
    keys
    |> Enum.sort_by(&(-:math.pow(:rand.uniform(), 1 / Map.get(weights, &1, 1))))
    |> Enum.take(count)
  end

  @doc "Every kind of loot, for picking a find."
  @spec loot() :: [atom()]
  def loot, do: Map.keys(@loot)

  @doc "Stats a piece of loot adds to the squad's checks."
  @spec loot_bonus(atom()) :: %{atom() => pos_integer()}
  def loot_bonus(item), do: Map.fetch!(@loot, item)

  @doc """
  A new raid for `members` (maps with `:name` and `:rarity`) along `route`,
  a random `route/0` by default. Members are told apart by `:index`, names
  may repeat. Each crossroads on the route gets two paths (`forks`), events
  that are on the route nowhere else.
  """
  @spec new([map()], [atom()]) :: map()
  def new(members, route \\ route()) do
    squad =
      members
      |> Enum.with_index()
      |> Enum.map(fn {member, index} ->
        member |> card() |> Map.merge(%{index: index, alive: true})
      end)

    forks =
      for crossroads <- route, crossroads?(crossroads), reduce: %{} do
        forks ->
          taken = route ++ Enum.concat(Map.values(forks))
          Map.put(forks, crossroads, draw(@common -- taken, @weights, 2))
      end

    %{
      squad: squad,
      route: route,
      forks: forks,
      step: 0,
      stash: [],
      karma: 0,
      last: nil
    }
  end

  @doc """
  A member's raid card: the battle card (`BattleRoom.card/1`) with the part
  that comes from the name cut to `@base_share` percent (1 at least), the
  rarity bonus kept whole. The gnome stays a joker.
  """
  @spec card(%{name: String.t(), rarity: atom()}) :: map()
  def card(%{rarity: :gnome} = member), do: BattleRoom.card(member)

  def card(member) do
    card = BattleRoom.card(member)
    bonus = BattleRoom.rarity_bonus(card.rarity)

    stats =
      Map.new(card.stats, fn {stat, value} ->
        {stat, max(div((value - bonus) * @base_share, 100), 1) + bonus}
      end)

    %{card | stats: stats}
  end

  @doc "The event the squad stands at, nil once the raid is over."
  @spec event(map()) :: atom() | nil
  def event(%{route: route, step: step} = raid),
    do: if(over?(raid), do: nil, else: Enum.at(route, step))

  @doc "Over once the route is walked or nobody is left."
  @spec over?(map()) :: boolean()
  def over?(%{route: route, step: step} = raid), do: step >= length(route) or alive(raid) == []

  @doc "Members still alive."
  @spec alive(map()) :: [map()]
  def alive(raid), do: Enum.filter(raid.squad, & &1.alive)

  @doc """
  The current event's options: `%{stat: nil}` for a safe one, otherwise the
  stat, the member who'd do it, the chance in percent and what a success
  brings (`reward`) and a failure costs (`risk`). At a crossroads each is a
  safe one with the event it leads to in `path`.
  """
  @spec options(map()) :: [map()]
  def options(raid) do
    event = event(raid)

    case raid.forks do
      %{^event => paths} -> Enum.map(paths, &%{option(raid, event, :safe) | path: &1})
      _forks -> @events |> Map.get(event, []) |> Enum.map(&option(raid, event, &1))
    end
  end

  defp option(_raid, _event, :safe),
    do: %{stat: nil, member: nil, chance: nil, reward: nil, risk: nil, path: nil}

  defp option(raid, event, {stat, difficulty, success, failure}) do
    member = raid |> alive() |> Enum.max_by(&with_loot(raid, &1, stat))
    difficulty = difficulty - karma_ease(raid, event, stat)
    chance = (with_loot(raid, member, stat) - difficulty) |> max(5) |> min(95)
    %{stat: stat, member: member, chance: chance, reward: success, risk: failure, path: nil}
  end

  # talking to scavs (a luck check at a scav event) goes as the squad's karma
  defp karma_ease(raid, event, :luck) when event in @scav_events, do: raid.karma * @karma_step
  defp karma_ease(_raid, _event, _stat), do: 0

  # a member's stat with the bonuses of the loot they found
  defp with_loot(raid, member, stat),
    do: member.stats[stat] + Map.get(loot_bonuses(raid, member), stat, 0)

  @doc """
  What a member's loot adds to each stat, `%{stat => bonus}` (a bonus may be
  negative). Empty for a fallen member: their loot doesn't work.
  """
  @spec loot_bonuses(map(), map()) :: %{atom() => integer()}
  def loot_bonuses(_raid, %{alive: false}), do: %{}

  def loot_bonuses(raid, member) do
    for %{item: item, owner: owner} <- raid.stash, owner == member.index, reduce: %{} do
      bonuses -> Map.merge(bonuses, @loot[item], fn _stat, a, b -> a + b end)
    end
  end

  @doc "Whether a stash entry works: its finder is alive."
  @spec active?(map(), map()) :: boolean()
  def active?(raid, %{owner: owner}), do: Enum.at(raid.squad, owner).alive

  @doc """
  Takes option `index` of the current event: a check succeeds when `roll`
  (1..100) is within its chance; the loot found is `item`. `last` holds what
  happened, for the page to tell.
  """
  @spec choose(map(), non_neg_integer(), 1..100, atom()) :: map()
  def choose(raid, index, roll, item \\ random_item()) do
    event = event(raid)
    safe = %{event: event, outcome: :safe, member: nil, index: nil, item: nil, stat: nil}

    case event && pick(raid, event, index) do
      nil ->
        raid

      {:path, path} ->
        route = List.insert_at(raid.route, raid.step + 1, path)
        step(%{raid | route: route}, Map.merge(safe, %{outcome: :path, path: path}))

      :safe ->
        step(raid, safe)

      option ->
        check(raid, event, option, roll, item)
    end
  end

  # option `index` of an event: a path at a crossroads, otherwise as listed
  defp pick(%{forks: forks}, event, index) when is_map_key(forks, event) do
    case Enum.at(forks[event], index) do
      nil -> nil
      path -> {:path, path}
    end
  end

  defp pick(_raid, event, index), do: Enum.at(Map.fetch!(@events, event), index)

  defp check(raid, event, {stat, _difficulty, success, failure} = option, roll, item) do
    %{member: member, chance: chance} = option(raid, event, option)
    outcome = if roll <= chance, do: success, else: failure

    settle(raid, outcome, member, item, %{
      event: event,
      outcome: outcome,
      member: member.name,
      index: member.index,
      item: nil,
      stat: stat
    })
  end

  defp settle(raid, :lose, member, _item, last),
    do: raid |> set_alive(member.index, false) |> step(last)

  defp settle(raid, :loot, member, item, last),
    do:
      step(%{raid | stash: raid.stash ++ [%{item: item, owner: member.index}]}, %{
        last
        | item: item
      })

  # the last item found goes first; an empty stash has nothing to give
  # the last active item goes: a fallen member's loot is no use to give away
  defp settle(raid, :drop, _member, _item, last) do
    active = for {entry, index} <- Enum.with_index(raid.stash), active?(raid, entry), do: index

    case List.last(active) do
      nil ->
        step(raid, last)

      index ->
        {dropped, stash} = List.pop_at(raid.stash, index)
        step(%{raid | stash: stash}, %{last | item: dropped.item})
    end
  end

  defp settle(raid, :revive, _member, _item, last) do
    case Enum.find(raid.squad, &(not &1.alive)) do
      nil ->
        step(raid, %{last | outcome: :pass})

      fallen ->
        raid
        |> set_alive(fallen.index, true)
        |> step(%{last | member: fallen.name, index: fallen.index})
    end
  end

  defp settle(raid, :train, member, _item, last),
    do: raid |> add_stat(member.index, last.stat, @stat_step) |> step(last)

  defp settle(raid, :wound, member, _item, last),
    do: raid |> add_stat(member.index, last.stat, -@stat_step) |> step(last)

  defp settle(raid, :promote, member, _item, last) do
    last = if next_rarity(member.rarity), do: last, else: %{last | outcome: :train}
    raid |> rank_up(member, last.stat) |> step(last)
  end

  defp settle(raid, :trophy, member, _item, last) do
    trophy = trophy(last.event)

    %{raid | stash: raid.stash ++ [%{item: trophy, owner: member.index}]}
    |> rank_up(member, last.stat)
    |> step(%{last | item: trophy})
  end

  defp settle(raid, _pass_or_nothing, _member, _item, last), do: step(raid, last)

  defp set_alive(raid, index, alive), do: update_member(raid, index, &%{&1 | alive: alive})

  defp add_stat(raid, index, stat, delta),
    do:
      update_member(raid, index, fn member ->
        update_in(member.stats[stat], &max(&1 + delta, 1))
      end)

  # a promotion; at the top the checked stat is trained instead
  defp rank_up(raid, member, stat) do
    case next_rarity(member.rarity) do
      nil -> add_stat(raid, member.index, stat, @stat_step)
      rarity -> promote(raid, member.index, rarity)
    end
  end

  # the stats keep what the raid did to them and take the new rarity's bonus on top
  defp promote(raid, index, rarity) do
    update_member(raid, index, fn member ->
      delta = BattleRoom.rarity_bonus(rarity) - BattleRoom.rarity_bonus(member.rarity)

      %{
        member
        | rarity: rarity,
          stats: Map.new(member.stats, fn {stat, value} -> {stat, value + delta} end)
      }
    end)
  end

  # nil at the top: a legendary has nowhere to go, the gnome is off the scale
  defp next_rarity(rarity) do
    case Enum.find_index(@rarities, &(&1 == rarity)) do
      nil -> nil
      index -> Enum.at(@rarities, index + 1)
    end
  end

  defp update_member(raid, index, fun), do: update_in(raid.squad, &List.update_at(&1, index, fun))

  defp step(raid, last) do
    {follow_up, route} = follow(raid, Map.get(@chains, {last.event, last.outcome}))

    karma =
      (raid.karma + Map.get(@karma, {last.event, last.stat}, 0))
      |> max(-@karma_limit)
      |> min(@karma_limit)

    %{
      raid
      | route: route,
        step: raid.step + 1,
        karma: karma,
        last: Map.merge(last, %{follow_up: follow_up, karma: karma - raid.karma})
    }
  end

  # a chain's event comes `delay` events later, before the last one at the
  # latest: the route ends where it did, so the last event starts no chain
  defp follow(%{route: route, step: step}, {event, delay}) when step < length(route) - 1,
    do: {event, List.insert_at(route, min(step + delay, length(route) - 1), event)}

  defp follow(raid, _chain), do: {nil, raid.route}
end
