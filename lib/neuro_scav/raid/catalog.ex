defmodule NeuroScav.Raid.Catalog do
  @moduledoc """
  What raids are made of: every event, every piece of loot, the weather and
  the times of day, checked as the catalog compiles. `NeuroScav.Raid` plays
  them and takes the catalog at compile time (`compiled/0`). A new event is an
  entry here plus its texts in `priv/gettext` (title, text and one label per
  option checking a stat or needing an item).
  """

  # An event: its options, or a map with `options` and what else it is:
  #
  # - `weight`: how often it comes up on a route, 1 unless given
  # - `trophy`: a boss, the loot beating it brings
  # - `chain`: %{outcome => {the event it brings, how many events later}}
  # - `karma`: %{stat => how the scavs take the option checking it}
  # - `modes`: %{stat => who makes that check}: `:weakest` (the one worst at
  #   it, a stealthy one: the loudest gives the squad away) or `:each` (every
  #   alive member, one roll for all: the ones it beats bear the failure)
  # - `scav: true`: a scav event, karma eases its luck checks (talks with scavs)
  # - `gnome: true`: a gnome, after the squad's loot
  # - `search: true`: no options of its own but a search, see `NeuroScav.Raid`
  # - `exit: true`: an exit, on the map's last layer only; through it the raid ends
  #
  # option: {stat, difficulty, on success, on failure}, :safe, a key
  # {:key, item, on success}: no check, the success sure if an alive member
  # has the item (it stays theirs), locked if nobody does; or a condition, a
  # sure pass as well: `:pay` takes the stash's last active item (locked with
  # none), `{:karma, n}` needs the scavs' karma at n at least. An option is
  # told apart by its stat (labels, karma, `last.stat`): an event checks a
  # stat once.
  @events %{
    pmc: [{:strength, 0, :pass, :lose}, {:agility, 10, :pass, :lose}],
    reshala: %{
      options: [{:strength, 15, :loot, :lose}, {:agility, 5, :pass, :lose}],
      modes: %{agility: :weakest},
      karma: %{strength: -1},
      chain: %{loot: {:reshala_guards, 2}}
    },
    sniper: [{:agility, 0, :pass, :lose}, {:luck, -10, :pass, :lose}, {:key, :altyn, :pass}],
    mines: %{
      options: [{:agility, 0, :pass, :wound}, {:luck, 10, :pass, :lose}],
      modes: %{agility: :each}
    },
    office: [{:strength, 10, :loot, :nothing}, :safe],
    bait: %{options: [{:agility, 15, :loot, :lose}, :safe], chain: %{safe: {:ambush, 2}}},
    killa: %{
      options: [{:strength, 15, :loot, :lose}, {:luck, 5, :pass, :lose}],
      modes: %{luck: :weakest}
    },
    wounded: %{
      options: [{:luck, 0, :loot, :nothing}, :safe],
      scav: true,
      karma: %{luck: 1},
      chain: %{loot: {:debtor, 3}}
    },
    tagilla: [{:strength, 20, :loot, :lose}, {:agility, 5, :pass, :lose}],
    shturman: [{:agility, 10, :loot, :lose}, {:luck, 0, :pass, :lose}],
    cultists: %{
      options: [{:agility, 5, :pass, :lose}, {:luck, 10, :pass, :lose}, {:key, :nvg, :pass}],
      modes: %{luck: :weakest}
    },
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
    tripwire: %{
      options: [{:agility, -5, :pass, :wound}, {:luck, 10, :loot, :lose}],
      modes: %{agility: :each}
    },
    dead_pmc: %{options: [{:luck, 5, :loot, :lose}, :safe], chain: %{loot: {:pmc_killer, 2}}},
    labs: [
      {:strength, 25, :loot, :lose},
      {:agility, 20, :loot, :lose},
      {:key, :keycard, :loot},
      :safe
    ],
    obdolbos: [{:luck, 0, :train, :wound}, :safe],
    skirmish: [{:strength, 5, :train, :wound}, {:agility, 0, :pass, :lose}],
    stairs: [{:agility, 10, :train, :wound}, :safe],
    # the promoting ones are rare
    veteran: %{options: [{:strength, 20, :promote, :wound}, :safe], weight: 0.12},
    lightkeeper: %{options: [{:agility, 25, :promote, :lose}, :safe], weight: 0.12},
    rogues: [{:agility, 20, :loot, :lose}, {:luck, 10, :pass, :drop}],
    bunker: [{:luck, 5, :loot, :lose}, :safe],
    mechanic: [{:agility, 10, :loot, :lose}, :safe],
    train: [{:agility, 5, :pass, :stall}, :safe],
    trunk: [{:luck, 0, :loot, :wound}, :safe],
    goons: %{
      options: [{:strength, 30, :loot, :lose}, {:agility, 10, :pass, :lose}, :safe],
      modes: %{agility: :weakest}
    },
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
    # bosses: no way around, only a fight for the trophy or a costly escape. A
    # fight is no harder than a plain check: by the time a boss comes the squad
    # is worn, and a loss is a death, so it's won about 4 times in 10 (mix raid.sim)
    kaban: %{
      options: [{:strength, 0, :trophy, :lose}, {:agility, 15, :pass, :wound}],
      trophy: :pkm
    },
    partisan: %{
      options: [{:agility, 0, :trophy, :lose}, {:luck, 15, :pass, :wound}],
      trophy: :ghillie
    },
    priest: %{
      options: [{:luck, 0, :trophy, :lose}, {:agility, 15, :pass, :wound}],
      trophy: :amulet
    },
    # the toughest, won about 1 time in 4: its trophy is legendary
    komar: %{
      options: [{:agility, 5, :trophy, :lose}, {:luck, 15, :pass, :wound}],
      trophy: :komar_wings
    },
    # exits: the squad gets out whatever comes of it, at a price; none stalls
    exit_car: %{
      options: [:pay, {:luck, 5, :pass, :drop}, {:agility, 10, :pass, :wound}],
      exit: true
    },
    exit_coop: %{
      options: [{:karma, 1}, {:luck, 10, :pass, :lose}, {:agility, 15, :pass, :wound}],
      exit: true,
      scav: true
    },
    exit_bunker: %{
      options: [
        {:key, :keycard, :pass},
        {:strength, 15, :pass, :wound},
        {:luck, 15, :pass, :drop}
      ],
      exit: true
    },
    exit_boat: %{options: [{:agility, 5, :pass, :wound}, {:luck, 0, :pass, :drop}], exit: true},
    exit_train: %{options: [{:luck, 5, :pass, :wound}, {:agility, 10, :pass, :lose}], exit: true},
    # searches: one more box, and one more, till the squad leaves or gets hurt
    abandoned_store: %{search: true},
    dorm_room: %{search: true},
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
    desync: [{:luck, 10, :pass, :lose}, {:agility, 0, :pass, :stall}],
    extract_campers: [{:agility, 15, :pass, :lose}, {:luck, 10, :pass, :drop}],
    prapor_quest: [{:luck, 5, :train, :nothing}, :safe],
    sleeping_scav: %{options: [{:agility, 5, :loot, :wound}, :safe], karma: %{agility: -1}},
    streets_fps: [{:agility, 15, :pass, :stall}, {:luck, 5, :train, :nothing}],
    bear_usec: [{:luck, 5, :loot, :nothing}, {:agility, 10, :pass, :lose}],
    grenade_scav: [{:agility, 0, :loot, :lose}, {:luck, 10, :pass, :wound}],
    door_key: [
      {:strength, 10, :loot, :wound},
      {:luck, 20, :loot, :nothing},
      {:key, :keycard, :loot}
    ],
    # a stall: clearing the way may take so long that something else turns up
    roadblock: [{:strength, 10, :pass, :stall}, {:agility, 5, :pass, :wound}],
    # Tarkov once more
    elevator: [
      {:agility, 10, :pass, :stall},
      {:strength, 5, :pass, :wound},
      {:key, :keycard, :pass}
    ],
    extract_queue: %{
      options: [{:agility, 10, :pass, :lose}, {:strength, 15, :loot, :lose}],
      modes: %{agility: :weakest}
    },
    moonshine_still: [{:luck, 5, :train, :wound}, :safe],
    quest_item: [{:agility, 15, :loot, :lose}, :safe],
    mosin_chad: [{:agility, 10, :pass, :lose}, {:strength, 10, :loot, :lose}],
    wipe_day: [{:strength, 0, :train, :wound}, :safe],
    therapist_quest: [{:luck, 15, :loot, :nothing}, :safe],
    footsteps: %{
      options: [{:luck, 10, :pass, :lose}, {:agility, 5, :pass, :wound}],
      modes: %{agility: :weakest}
    },
    bush_wookie: [{:strength, 10, :loot, :lose}, {:luck, 5, :pass, :drop}],
    chatty_scav: %{
      options: [{:luck, 5, :pass, :wound}, {:strength, 10, :loot, :lose}],
      scav: true,
      karma: %{strength: -1}
    },
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
    # consumables, see @consumables
    medkit: %{},
    # trophies, see @trophies
    pkm: %{strength: 20},
    ghillie: %{agility: 15, luck: 5},
    amulet: %{luck: 20},
    komar_wings: %{luck: 40}
  }

  # how often a kind of loot turns up, 1 unless listed: the valuables are rare
  @loot_weights %{ledx: 0.3, keycard: 0.3, slick: 0.5}

  # consumables: loot the squad shares and spends by itself, once, on what it
  # spares a member from: a medkit turns a death into a wound, propital takes
  # a wound away (till then it's loot like any other)
  @consumables %{medkit: :lose, propital: :wound}

  # the weather, one for a raid, drawn by weight: mostly clear, now and then
  # something that adds a little to some checks, more often takes
  @weathers %{
    clear: %{weight: 6, stats: %{}},
    fog: %{weight: 1, stats: %{strength: -10, agility: 5}},
    rain: %{weight: 1, stats: %{agility: -5, luck: -5}},
    wind: %{weight: 1, stats: %{strength: -5}},
    blizzard: %{weight: 1, stats: %{agility: -10}},
    heat: %{weight: 1, stats: %{strength: -5, agility: -5}},
    storm: %{weight: 1, stats: %{luck: -10}}
  }

  # the times of day in turn, round and round, and what each adds to a kind
  # of check: a fight (strength), a search (a check for loot) or hiding (an
  # escape or a stealthy check, see `modes`)
  @daytimes [
    morning: %{search: 5},
    day: %{fight: 5, search: 5, hide: -5},
    evening: %{hide: 5},
    night: %{hide: 10, fight: -5, search: -5}
  ]

  # what a member is like, drawn from the name, see `NeuroScav.Raid`
  @traits [:greedy, :coward, :chatty, :lucky, :psycho]

  # every event as a map; a search has no options
  @specs Map.new(@events, fn
           {event, options} when is_list(options) -> {event, %{options: options}}
           {event, spec} -> {event, Map.put_new(spec, :options, [])}
         end)

  # The catalog is checked as it compiles: a slip in it would show only in a
  # raid (a chain to an unknown event stops it for good, an unknown trophy
  # crashes it) or never (an unknown key, a chain on an outcome that doesn't
  # come, karma for an unchecked stat: all just ignored; an unknown outcome
  # would be a plain pass; a check made by `:each` of the squad needs a pass
  # to bring and a wound to cost).
  @spec_keys [
    :options,
    :weight,
    :trophy,
    :chain,
    :karma,
    :modes,
    :scav,
    :gnome,
    :search,
    :exit
  ]
  @successes [:pass, :loot, :revive, :train, :promote, :trophy]
  @failures [:lose, :wound, :drop, :nothing, :stall]

  for {event, spec} <- @specs do
    checks =
      for {stat, _difficulty, success, failure} <- spec.options, do: {stat, success, failure}

    keys = for {:key, item, success} <- spec.options, do: {item, success}
    stats = for {stat, _success, _failure} <- checks, do: stat
    safe = if :safe in spec.options, do: [:safe], else: []

    conditions =
      for option <- spec.options,
          option == :pay or match?({:karma, level} when is_integer(level) and level > 0, option),
          do: option

    outcomes =
      safe ++
        Enum.flat_map(checks, fn {_stat, success, failure} -> [success, failure] end) ++
        for({_item, success} <- keys, do: success)

    chain = Map.get(spec, :chain, %{})
    modes = Map.get(spec, :modes, %{})
    unknown = Map.keys(spec) -- @spec_keys

    problems =
      Enum.filter(
        [
          unknown != [] && "unknown keys #{inspect(unknown)}",
          length(checks) + length(keys) + length(safe) + length(conditions) !=
            length(spec.options) &&
            "an option of no known shape",
          Enum.any?(checks, fn {_stat, success, failure} ->
            success not in @successes or failure not in @failures
          end) && "an unknown outcome",
          Enum.any?(keys, fn {item, success} ->
            not Map.has_key?(@loot, item) or success not in @successes
          end) && "a key of unknown loot or outcome",
          Map.keys(modes) -- stats != [] && "a mode for a stat no option checks",
          Enum.any?(modes, fn {_stat, mode} -> mode not in [:weakest, :each] end) &&
            "an unknown mode",
          Enum.any?(checks, fn {stat, success, failure} ->
            modes[stat] == :each and (success != :pass or failure != :wound)
          end) && "a check by each that doesn't pass or wound",
          stats != Enum.uniq(stats) && "two options check the same stat",
          Map.keys(chain) -- outcomes != [] && "a chain on an outcome its options don't have",
          Enum.any?(chain, fn {_outcome, {follow_up, _delay}} ->
            not Map.has_key?(@specs, follow_up)
          end) && "a chain to an unknown event",
          Map.has_key?(spec, :trophy) && not Map.has_key?(@loot, spec.trophy) &&
            "an unknown trophy",
          Map.keys(Map.get(spec, :karma, %{})) -- stats != [] &&
            "karma for a stat no option checks",
          Map.get(spec, :search) && spec.options != [] && "a search with options of its own",
          Map.get(spec, :exit) && :stall in outcomes && "an exit that stalls"
        ],
        &is_binary/1
      )

    if problems != [],
      do: raise(CompileError, description: "raid event #{event}: #{Enum.join(problems, "; ")}")
  end

  @exits for {event, %{exit: true}} <- @specs, do: event
  @searches for {event, %{search: true}} <- @specs, do: event
  @bosses for {event, %{trophy: _trophy}} <- @specs, do: event
  @trophies for {event, %{trophy: trophy}} <- @specs, into: %{}, do: {event, trophy}
  @weights for {event, %{weight: weight}} <- @specs, into: %{}, do: {event, weight}
  @gnomes for {event, %{gnome: true}} <- @specs, do: event
  # where a member may be lost
  @deadly for {event, spec} <- @specs,
              Enum.any?(spec.options, &match?({_stat, _difficulty, _success, :lose}, &1)),
              do: event

  # {event, the stat checked} => how the scavs take it
  @karma for {event, %{karma: karma}} <- @specs,
             {stat, change} <- karma,
             into: %{},
             do: {{event, stat}, change}
  @scav_events for {event, %{scav: true}} <- @specs, do: event

  # {event, outcome} => {the event it brings, how many events later}
  @chains for {event, %{chain: chain}} <- @specs,
              {outcome, follow_up} <- chain,
              into: %{},
              do: {{event, outcome}, follow_up}
  @follow_ups for {_trigger, {event, _delay}} <- @chains, do: event
  # what a random map's nodes are drawn from, apart from its exits and boss
  @common Map.keys(@specs) -- (@bosses ++ @follow_ups ++ @exits)
  # what a stall may bring: a common event that can't stall in its turn
  @detours for event <- @common,
               not Enum.any?(@specs[event].options, &match?({_, _, _, :stall}, &1)),
               do: event

  # {event, stat} => who makes that check, :best unless given
  @modes for {event, %{modes: modes}} <- @specs,
             {stat, mode} <- modes,
             into: %{},
             do: {{event, stat}, mode}

  # What kind of event a node on the map is, told before the squad gets there:
  # the first that fits, a boss, an exit and so on down to a plain danger.
  kind = fn spec ->
    outcomes =
      for {_stat, _difficulty, success, failure} <- spec.options,
          outcome <- [success, failure],
          do: outcome

    cond do
      Map.has_key?(spec, :trophy) -> :boss
      Map.get(spec, :exit) -> :exit
      Map.get(spec, :search) -> :search
      Map.get(spec, :gnome) -> :gnome
      Map.get(spec, :scav) -> :scav
      :promote in outcomes -> :rare
      :loot in outcomes -> :loot
      :lose in outcomes -> :fight
      true -> :hazard
    end
  end

  @kinds Map.new(@specs, fn {event, spec} -> {event, kind.(spec)} end)

  @doc """
  The catalog as `NeuroScav.Raid` takes it at compile time: the events as
  maps (`specs`), what each kind of them is, the loot, the weather and the
  times of day.
  """
  @spec compiled() :: map()
  def compiled do
    %{
      specs: @specs,
      modes: @modes,
      consumables: @consumables,
      weathers: @weathers,
      daytimes: @daytimes,
      exits: @exits,
      kinds: @kinds,
      searches: @searches,
      traits: @traits,
      bosses: @bosses,
      trophies: @trophies,
      weights: @weights,
      gnomes: @gnomes,
      deadly: @deadly,
      karma: @karma,
      scav_events: @scav_events,
      chains: @chains,
      follow_ups: @follow_ups,
      common: @common,
      detours: @detours,
      loot: @loot,
      loot_weights: @loot_weights
    }
  end
end
