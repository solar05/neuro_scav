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

  A squad can't run forever: a retreat is the safe option or a check that only
  lets the squad by and can't kill (an escape). After `@retreat_limit` of them
  in a row the retreats are locked (`locked: true` in `options/1`) until the
  squad takes something else, unless an event has nothing else. A crossroads
  path is neither.

  A raid is plain data: the page keeps it, every step returns a new one. The
  roll (1..100) and the loot found are arguments, so a raid is fully
  predictable in tests.
  """

  alias NeuroScav.BattleRoom

  # An event: its options, or a map with `options` and what else it is:
  #
  # - `weight`: how often it comes up on a route, 1 unless given
  # - `trophy`: a boss, the loot beating it brings
  # - `chain`: %{outcome => {the event it brings, how many events later}}
  # - `karma`: %{stat => how the scavs take the option checking it}
  # - `scav: true`: a scav event, karma eases its luck checks (talks with scavs)
  # - `gnome: true`: a gnome, after the squad's loot
  # - `crossroads: true`: no options of its own but paths, see `forks` in new/2
  #
  # option: {stat, difficulty, on success, on failure} or :safe. An option is
  # told apart by its stat (labels, karma, `last.stat`): an event checks a stat once.
  @events %{
    pmc: [{:strength, 0, :pass, :lose}, {:agility, 10, :pass, :lose}],
    reshala: %{
      options: [{:strength, 15, :loot, :lose}, {:agility, 5, :pass, :lose}],
      karma: %{strength: -1},
      chain: %{loot: {:reshala_guards, 2}}
    },
    sniper: [{:agility, 0, :pass, :lose}, {:luck, -10, :pass, :lose}],
    mines: [{:agility, 0, :pass, :lose}, {:luck, 10, :pass, :lose}],
    office: [{:strength, 10, :loot, :nothing}, :safe],
    bait: %{options: [{:agility, 15, :loot, :lose}, :safe], chain: %{safe: {:ambush, 2}}},
    killa: [{:strength, 15, :loot, :lose}, {:luck, 5, :pass, :lose}],
    wounded: %{
      options: [{:luck, 0, :loot, :nothing}, :safe],
      scav: true,
      karma: %{luck: 1},
      chain: %{loot: {:debtor, 3}}
    },
    tagilla: [{:strength, 20, :loot, :lose}, {:agility, 5, :pass, :lose}],
    shturman: [{:agility, 10, :loot, :lose}, {:luck, 0, :pass, :lose}],
    cultists: [{:agility, 5, :pass, :lose}, {:luck, 10, :pass, :lose}],
    raiders: [{:strength, 20, :loot, :lose}, {:agility, 10, :pass, :lose}],
    toll: %{options: [{:luck, 0, :pass, :drop}, :safe], scav: true},
    airdrop: %{
      options: [{:agility, 20, :loot, :lose}, :safe],
      chain: %{loot: {:drop_hunters, 1}}
    },
    medic: %{options: [{:luck, 0, :revive, :nothing}, :safe], scav: true},
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
    dead_pmc: %{options: [{:luck, 5, :loot, :lose}, :safe], chain: %{loot: {:pmc_killer, 2}}},
    labs: [{:strength, 25, :loot, :lose}, {:agility, 20, :loot, :lose}, :safe],
    obdolbos: [{:luck, 0, :train, :wound}, :safe],
    skirmish: [{:strength, 5, :train, :wound}, {:agility, 0, :pass, :lose}],
    stairs: [{:agility, 10, :train, :wound}, :safe],
    # the promoting ones are rare
    veteran: %{options: [{:strength, 20, :promote, :wound}, :safe], weight: 0.12},
    lightkeeper: %{options: [{:agility, 25, :promote, :lose}, :safe], weight: 0.12},
    rogues: [{:agility, 20, :loot, :lose}, {:luck, 10, :pass, :drop}],
    bunker: [{:luck, 5, :loot, :lose}, :safe],
    mechanic: [{:agility, 10, :loot, :lose}, :safe],
    train: [{:agility, 5, :pass, :lose}, :safe],
    trunk: [{:luck, 0, :loot, :wound}, :safe],
    goons: [{:strength, 30, :loot, :lose}, {:agility, 10, :pass, :lose}, :safe],
    flea: %{options: [{:luck, 0, :loot, :drop}, :safe], scav: true},
    tower: [{:agility, 5, :train, :lose}, :safe],
    # chains: only ever brought by another event
    reshala_guards: %{
      options: [{:strength, 20, :loot, :lose}, {:agility, 10, :pass, :wound}],
      karma: %{strength: -1}
    },
    ambush: [{:agility, 10, :pass, :wound}, {:strength, 15, :loot, :lose}],
    debtor: %{options: [{:luck, -15, :revive, :nothing}, :safe], scav: true},
    drop_hunters: [{:agility, 15, :pass, :drop}, {:strength, 20, :loot, :lose}],
    pmc_killer: [{:strength, 15, :loot, :lose}, {:luck, 10, :pass, :drop}],
    # bosses: no way around, only a fight for the trophy or a costly escape
    kaban: %{
      options: [{:strength, 30, :trophy, :lose}, {:agility, 15, :pass, :wound}],
      trophy: :pkm
    },
    partisan: %{
      options: [{:agility, 30, :trophy, :lose}, {:luck, 15, :pass, :wound}],
      trophy: :ghillie
    },
    priest: %{
      options: [{:luck, 30, :trophy, :lose}, {:agility, 15, :pass, :wound}],
      trophy: :amulet
    },
    # the toughest: its trophy is legendary
    komar: %{
      options: [{:agility, 35, :trophy, :lose}, {:luck, 15, :pass, :wound}],
      trophy: :komar_wings
    },
    # crossroads
    fork_road: %{crossroads: true, weight: 0.5},
    fork_tunnel: %{crossroads: true, weight: 0.5},
    radio: %{crossroads: true, weight: 0.5},
    # scavs
    scav_camp: %{
      options: [{:luck, 5, :loot, :nothing}, {:strength, 10, :loot, :lose}, :safe],
      scav: true,
      karma: %{luck: 1, strength: -2}
    },
    fence: %{options: [{:luck, 15, :loot, :nothing}, :safe], scav: true},
    scav_patrol: %{
      options: [{:luck, 10, :pass, :wound}, {:strength, 15, :loot, :lose}],
      scav: true,
      karma: %{strength: -1}
    },
    lost_scav: %{options: [{:agility, 10, :train, :wound}, :safe], karma: %{agility: 1}},
    # Tarkov as players know it
    axeman: [{:strength, 5, :loot, :lose}, {:agility, 10, :pass, :wound}],
    cheater: [{:luck, 25, :loot, :lose}, {:agility, 15, :pass, :lose}],
    desync: [{:luck, 10, :pass, :lose}, {:agility, 0, :pass, :wound}],
    extract_campers: [{:agility, 15, :pass, :lose}, {:luck, 10, :pass, :drop}],
    prapor_quest: [{:luck, 5, :train, :nothing}, :safe],
    sleeping_scav: %{options: [{:agility, 5, :loot, :wound}, :safe], karma: %{agility: -1}},
    streets_fps: [{:agility, 15, :pass, :wound}, {:luck, 5, :train, :nothing}],
    bear_usec: [{:luck, 5, :loot, :nothing}, {:agility, 10, :pass, :lose}],
    grenade_scav: [{:agility, 0, :loot, :lose}, {:luck, 10, :pass, :wound}],
    door_key: [{:strength, 10, :loot, :wound}, {:luck, 20, :loot, :nothing}],
    jaeger_quest: %{options: [{:agility, 25, :promote, :wound}, :safe], weight: 0.3},
    bitcoin_farm: %{
      options: [{:strength, 15, :loot, :lose}, {:luck, 10, :loot, :wound}],
      karma: %{strength: -1}
    },
    # gnomes: small, many and after your loot; whatever the squad tries with
    # the thief, a failure costs loot
    gnome_thief: %{
      options: [{:agility, 10, :loot, :drop}, {:luck, 5, :pass, :drop}],
      weight: 0.5,
      gnome: true
    },
    gnome_trader: %{options: [{:luck, 10, :loot, :drop}, :safe], weight: 0.5, gnome: true},
    gnome_ambush: %{
      options: [{:strength, 15, :loot, :lose}, {:agility, 10, :pass, :drop}],
      weight: 0.5,
      gnome: true
    },
    gnome_pmc: %{
      options: [{:strength, 20, :loot, :lose}, {:luck, 5, :pass, :drop}],
      weight: 0.5,
      gnome: true
    }
  }

  # every event as a map; a crossroads has no options
  @specs Map.new(@events, fn
           {event, options} when is_list(options) -> {event, %{options: options}}
           {event, spec} -> {event, Map.put_new(spec, :options, [])}
         end)

  for {event, %{options: options}} <- @specs,
      stats = for({stat, _difficulty, _success, _failure} <- options, do: stat),
      stats != Enum.uniq(stats) do
    raise CompileError, description: "raid event #{event}: two options check the same stat"
  end

  @crossroads for {event, %{crossroads: true}} <- @specs, do: event
  @bosses for {event, %{trophy: _trophy}} <- @specs, do: event
  @boss_chance 0.4
  @trophies for {event, %{trophy: trophy}} <- @specs, into: %{}, do: {event, trophy}
  @weights for {event, %{weight: weight}} <- @specs, into: %{}, do: {event, weight}
  @gnomes for {event, %{gnome: true}} <- @specs, do: event

  # {event, the stat checked} => how the scavs take it
  @karma for {event, %{karma: karma}} <- @specs,
             {stat, change} <- karma,
             into: %{},
             do: {{event, stat}, change}
  @karma_limit 3
  @karma_step 5
  @scav_events for {event, %{scav: true}} <- @specs, do: event

  # {event, outcome} => {the event it brings, how many events later}
  @chains for {event, %{chain: chain}} <- @specs,
              {outcome, follow_up} <- chain,
              into: %{},
              do: {{event, outcome}, follow_up}
  @follow_ups for {_trigger, {event, _delay}} <- @chains, do: event
  # what a random route or a crossroads path is drawn from
  @common Map.keys(@specs) -- (@bosses ++ @follow_ups ++ @crossroads)

  @rarities [:common, :uncommon, :rare, :epic, :legendary]
  @stat_step 10
  # the share (%) of a battle card's name part a raid stat keeps: with whole
  # cards the best of five passes nearly every check
  @base_share 60

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
  # retreats in a row a squad may make: then it has to take a risk
  @retreat_limit 2
  # an option with no check: a safe one or a crossroads path
  @no_check %{
    stat: nil,
    member: nil,
    chance: nil,
    reward: nil,
    risk: nil,
    path: nil,
    retreat: false,
    locked: false
  }

  @doc "How many events a raid goes through, picked for each raid."
  @spec steps() :: Range.t()
  def steps, do: @steps

  @doc "How many retreats in a row a squad may make before it has to take a risk."
  @spec retreat_limit() :: pos_integer()
  def retreat_limit, do: @retreat_limit

  @doc "Every event."
  @spec events() :: [atom()]
  def events, do: Map.keys(@specs)

  @doc "How much a member's stat grows or drops on `:train` and `:wound`."
  @spec stat_step() :: pos_integer()
  def stat_step, do: @stat_step

  @doc "Whether an event is a boss."
  @spec boss?(atom()) :: boolean()
  def boss?(event), do: event in @bosses

  @doc "Whether an event is a gnome's: they're after the squad's loot."
  @spec gnome?(atom()) :: boolean()
  def gnome?(event), do: event in @gnomes

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
      retreats: 0,
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
  brings (`reward`) and a failure costs (`risk`). A `retreat` is `locked` once
  the squad has retreated `@retreat_limit` times in a row. At a crossroads
  each is an option with no check and the event it leads to in `path`.
  """
  @spec options(map()) :: [map()]
  def options(raid) do
    event = event(raid)

    case raid.forks do
      %{^event => paths} ->
        Enum.map(paths, &%{@no_check | path: &1})

      _forks ->
        for option <- options_of(event) do
          %{
            option(raid, event, option)
            | retreat: retreat?(option),
              locked: locked?(raid, event, option)
          }
        end
    end
  end

  defp option(_raid, _event, :safe), do: @no_check

  defp option(raid, event, {stat, difficulty, success, failure}) do
    member = raid |> alive() |> Enum.max_by(&with_loot(raid, &1, stat))
    difficulty = difficulty - karma_ease(raid, event, stat)
    chance = (with_loot(raid, member, stat) - difficulty) |> max(5) |> min(95)
    %{@no_check | stat: stat, member: member, chance: chance, reward: success, risk: failure}
  end

  # the squad has retreated as long as it may: now it takes a risk, unless
  # the event has nothing but retreats
  defp locked?(raid, event, option) do
    raid.retreats >= @retreat_limit and retreat?(option) and
      not Enum.all?(options_of(event), &retreat?/1)
  end

  # the safe option, or an escape: a check that only lets the squad by and can't kill
  defp retreat?(:safe), do: true
  defp retreat?({_stat, _difficulty, :pass, failure}), do: failure != :lose
  defp retreat?(_option), do: false

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
  happened, for the page to tell. A locked option changes nothing.
  """
  @spec choose(map(), non_neg_integer(), 1..100, atom()) :: map()
  def choose(raid, index, roll, item \\ random_item()) do
    event = event(raid)

    safe = %{
      event: event,
      outcome: :safe,
      member: nil,
      index: nil,
      item: nil,
      stat: nil,
      retreat: true
    }

    case event && pick(raid, event, index) do
      nil ->
        raid

      {:path, path} ->
        route = List.insert_at(raid.route, raid.step + 1, path)
        step(%{raid | route: route}, Map.merge(safe, %{outcome: :path, path: path, retreat: nil}))

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

  defp pick(raid, event, index) do
    option = Enum.at(options_of(event), index)
    if option && not locked?(raid, event, option), do: option
  end

  # an event's options as listed, none when there's no event
  defp options_of(event), do: get_in(@specs, [event, :options]) || []

  defp check(raid, event, {stat, _difficulty, success, failure} = option, roll, item) do
    %{member: member, chance: chance} = option(raid, event, option)
    outcome = if roll <= chance, do: success, else: failure

    settle(raid, outcome, member, item, %{
      event: event,
      outcome: outcome,
      member: member.name,
      index: member.index,
      item: nil,
      stat: stat,
      retreat: retreat?(option)
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
        retreats: retreats(raid.retreats, last.retreat),
        last: Map.merge(last, %{follow_up: follow_up, karma: karma - raid.karma})
    }
  end

  # retreats in a row: a retreat counts up, a risk taken ends them, a
  # crossroads path (nil) is neither
  defp retreats(count, true), do: count + 1
  defp retreats(count, nil), do: count
  defp retreats(_count, false), do: 0

  # a chain's event comes `delay` events later, before the last one at the
  # latest: the route ends where it did, so the last event starts no chain
  defp follow(%{route: route, step: step}, {event, delay}) when step < length(route) - 1,
    do: {event, List.insert_at(route, min(step + delay, length(route) - 1), event)}

  defp follow(raid, _chain), do: {nil, raid.route}
end
