defmodule NeuroScav.Raid.Catalog do
  @moduledoc """
  What raids are made of: every event and every piece of loot, checked as the
  catalog compiles. `NeuroScav.Raid` plays them and takes the catalog at
  compile time (`compiled/0`). A new event is an entry here plus its texts in
  `priv/gettext` (title, text and one label per option checking a stat).
  """

  # An event: its options, or a map with `options` and what else it is:
  #
  # - `weight`: how often it comes up on a route, 1 unless given
  # - `trophy`: a boss, the loot beating it brings
  # - `chain`: %{outcome => {the event it brings, how many events later}}
  # - `karma`: %{stat => how the scavs take the option checking it}
  # - `scav: true`: a scav event, karma eases its luck checks (talks with scavs)
  # - `gnome: true`: a gnome, after the squad's loot
  # - `crossroads: true`: no options of its own but paths, see `NeuroScav.Raid.new/3`
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

  # every event as a map; a crossroads has no options
  @specs Map.new(@events, fn
           {event, options} when is_list(options) -> {event, %{options: options}}
           {event, spec} -> {event, Map.put_new(spec, :options, [])}
         end)

  # The catalog is checked as it compiles: a slip in it would show only in a
  # raid (a chain to an unknown event stops it for good, an unknown trophy
  # crashes it) or never (an unknown key, a chain on an outcome that doesn't
  # come, karma for an unchecked stat: all just ignored).
  @spec_keys [:options, :weight, :trophy, :chain, :karma, :scav, :gnome, :crossroads]

  for {event, spec} <- @specs do
    checks =
      for {stat, _difficulty, success, failure} <- spec.options, do: {stat, success, failure}

    stats = for {stat, _success, _failure} <- checks, do: stat
    safe = if :safe in spec.options, do: [:safe], else: []

    outcomes =
      safe ++ Enum.flat_map(checks, fn {_stat, success, failure} -> [success, failure] end)

    chain = Map.get(spec, :chain, %{})
    unknown = Map.keys(spec) -- @spec_keys

    problems =
      Enum.filter(
        [
          unknown != [] && "unknown keys #{inspect(unknown)}",
          stats != Enum.uniq(stats) && "two options check the same stat",
          Map.keys(chain) -- outcomes != [] && "a chain on an outcome its options don't have",
          Enum.any?(chain, fn {_outcome, {follow_up, _delay}} ->
            not Map.has_key?(@specs, follow_up)
          end) && "a chain to an unknown event",
          Map.has_key?(spec, :trophy) && not Map.has_key?(@loot, spec.trophy) &&
            "an unknown trophy",
          Map.keys(Map.get(spec, :karma, %{})) -- stats != [] &&
            "karma for a stat no option checks"
        ],
        &is_binary/1
      )

    if problems != [],
      do: raise(CompileError, description: "raid event #{event}: #{Enum.join(problems, "; ")}")
  end

  @crossroads for {event, %{crossroads: true}} <- @specs, do: event
  @bosses for {event, %{trophy: _trophy}} <- @specs, do: event
  @trophies for {event, %{trophy: trophy}} <- @specs, into: %{}, do: {event, trophy}
  @weights for {event, %{weight: weight}} <- @specs, into: %{}, do: {event, weight}
  @gnomes for {event, %{gnome: true}} <- @specs, do: event

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
  # what a random route or a crossroads path is drawn from
  @common Map.keys(@specs) -- (@bosses ++ @follow_ups ++ @crossroads)

  @doc """
  The catalog as `NeuroScav.Raid` takes it at compile time: the events as
  maps (`specs`), what each kind of them is, and the loot.
  """
  @spec compiled() :: map()
  def compiled do
    %{
      specs: @specs,
      crossroads: @crossroads,
      bosses: @bosses,
      trophies: @trophies,
      weights: @weights,
      gnomes: @gnomes,
      karma: @karma,
      scav_events: @scav_events,
      chains: @chains,
      follow_ups: @follow_ups,
      common: @common,
      loot: @loot,
      loot_weights: @loot_weights
    }
  end
end
