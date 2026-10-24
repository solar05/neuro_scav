defmodule NeuroScav.Raid do
  @moduledoc """
  A raid, Tarkov style: a short text roguelike for a squad of scavs.

  The squad crosses a map (`random_map/0`, its shape from
  `NeuroScav.Raid.Chart`): layers of nodes, an event at each, every node
  linked to one or two of the next layer's, the exits (`exit?/1`) on the last
  one; a map is `steps/0` layers long. Where the squad stands (`at/1`) it
  meets the node's event; that done, it picks the next node (`next_nodes/1`,
  `move/2`; with one way only it goes by itself), the first one too when
  there are several to start from. Through an exit the raid is over. The
  squad sees the nodes it may go to next and the exits as they are, the rest
  by their kind of event (`kind/1`), and those not at all at night or in the
  fog, the bosses and the camp's fire aside (`sight/2`), unless it has seen
  them before: what it has seen it remembers, by kind (`seen`).

  Each event offers two or three options; an option either needs a stat check,
  is safe (nothing happens), needs an item (a key: an alive member having it
  opens the way for sure, the item stays theirs; with nobody having it the
  option is locked) or has a condition, a sure way through as well, locked
  while it isn't met: a payment (`:paid`, the stash's last active item goes)
  or the scavs' trust (`:trusted`, karma high enough). Exits have them.
  A check is made by the alive member best at that stat counting their own
  loot (some checks by the worst one, `:weakest`, or by `:each`: one roll
  against everyone's chance, the failure for each it beats): the chance is
  the stat (`card/1`, a lowered battle card, with the squad's set bonus,
  `sets/1`) plus the bonuses of the loot that
  member found, minus the option's difficulty, eased or made harder by karma
  and the world (below), kept within 5..95%. Loot helps its finder only, and
  only while they're alive: a fallen member's loot stays in the stash,
  inactive, and works again if they come back. What a success brings and a
  failure costs depends on the option:

  - success: `:pass`, `:loot` (an item to the stash, `%{item, owner}` with
    the finder's index), `:revive` (the first fallen member is back; with
    nobody fallen the most wounded one is patched up, `:heal`, and with
    nobody wounded either it's a pass), `:train` (the
    member's checked stat grows by `stat_step/0`), `:promote` (the member's
    rarity goes one up, the stats grow by the difference of rarity bonuses;
    at the top it's a `:train`) or `:trophy` (a won boss fight: the boss's
    own loot, `trophy/1`, and a promotion, a training at the top)
  - failure: `:lose` (the member doesn't make it out), `:wound` (the checked
    stat drops by `stat_step/0`, to 1 at least), `:drop` (the last active
    item of the stash is gone), `:nothing` or `:stall` (the squad doesn't get
    by and stays where it is, before another event: see below)

  Wounds add up: from the second one a member bleeds (`bleeding?/1`), losing
  `@bleed` of every stat at every step, the third kills. The squad's
  consumables spend themselves on what they spare a member from (`last.used`
  tells): propital takes a wound away (`:spared`), a medkit turns a death,
  the third wound's too, into a wound that can't kill.

  The world (`world/1`): a weather for the raid, mostly clear, now and then
  one that eases or (more often) hardens checks of some stats; and the time
  of day, round and round from a random one, every `@daytime_turns` turns,
  easing or hardening a kind of check: a fight, a search or hiding.

  A stall doesn't move the squad on (`turn` counts every choice): where it
  stands it now meets a spare event instead, one of the `spares` drawn when
  the raid starts (events off the map that can't stall themselves). With none
  left it meets the same event again.

  A random map is one of Tarkov's locations (`locations/0`, `location/1`):
  its exits, its bosses, and its own events turn up there more often
  (`@local_weight` times). Maps pick events by weight: the promoting ones are
  rare. A map may get a boss (`boss?/1`), in the middle or just before the
  exits, where there's another way past if the map has one; beating one
  brings a trophy.

  Some outcomes start a chain: another event (never on a random map) catches
  up with the squad a few nodes later, at the last node at the latest, and
  comes before that node's own event. What brought it is in `last.follow_up`.

  Scavs remember: some options change the squad's `karma` (within
  ±`@karma_limit`, the change is in `last.karma`), and every point of it
  eases a luck check at a scav event by `@karma_step`, a bad one makes it harder.

  A squad can't run forever: a retreat is the safe option or a check that only
  lets the squad by and can't kill (an escape). After `@retreat_limit` of them
  in a row the retreats are locked (`locked: true` in `options/1`) until the
  squad takes something else, unless an event has nothing else; at an exit
  the squad is out anyway, nothing is locked for running. Leaving a search is
  neither.

  A search (`search?/1`) has no check of its own: the luckiest member looks
  through one more box, and one more, each look finding an item but riskier
  than the last (`@search_danger`, then `@search_step` more each time); the
  squad stays till it leaves (`:left`) or the searcher gets hurt and it moves
  on. A look's outcome is `:found`, the looks so far are in `searched`.

  Every member has a trait (`traits/0`), the same for a name every time, and
  now and then (a choice's quirk roll within `@quirk_chance`) one acts on
  their own, one at a choice (`last.quirk`): a greedy one goes for the loot
  (one more box, too), a psycho for the fight, whatever the squad chose; a
  coward leaves a deadly check to the next best one; a chatterbox talks scavs
  round (a luck check at a scav event) or gives the squad away when it hides
  (`@chatter`); a lucky one's failed check comes off after all.

  A camp (`camp?/1`), one on a random map, is a breather with three sure
  options, one to take: the most wounded member is patched up (`:heal`, locked
  with nobody wounded), the squad's weak spot is trained (`:train`: the stat
  the squad is worst at, counting the best member at it, grows on them), or
  the loot is repacked (`:repacked`: every item to the alive member best at
  what it adds, a fallen one's too, so it works again; locked when nothing
  would move). Resting is neither a retreat nor a risk.

  The events and the loot are in `NeuroScav.Raid.Catalog`.

  A raid is plain data: the page keeps it, every step returns a new one. The
  map (or a plain route), the world, the spares, the roll (1..100) and the
  loot found may all be given, so a raid is fully predictable in tests.
  """

  alias NeuroScav.Raid.{Catalog, Chart, Squad}

  @typedoc """
  What the last step did, every key always there, nil where it doesn't apply:
  the `event` and its `outcome`; the `member` (a name) and `index` of the one
  it happened to; the `item` found, dropped or stolen; the `stat` checked;
  whether it was a `retreat` (nil for leaving a search, neither); the event a
  chain brought (`follow_up`), the change of `karma` and
  the item `used` (a key, or a consumable spent); the `quirk`, `{what,
  name}`, when a member acted on their own. A check by each names all it beat
  in `member` (`:wounds` when they're more than one). A check's `roll` and
  the `chance` it was against, nil but the roll for a check by each (everyone
  had their own chance), both nil with no check.
  """
  @type last :: %{
          event: atom(),
          outcome: atom(),
          member: String.t() | nil,
          index: non_neg_integer() | nil,
          item: atom() | nil,
          stat: atom() | nil,
          retreat: boolean() | nil,
          follow_up: atom() | nil,
          karma: integer(),
          used: atom() | nil,
          quirk: {atom(), String.t()} | nil,
          roll: 1..100 | nil,
          chance: 5..95 | nil
        }
  @last %{
    event: nil,
    outcome: nil,
    member: nil,
    index: nil,
    item: nil,
    stat: nil,
    retreat: nil,
    follow_up: nil,
    karma: 0,
    used: nil,
    quirk: nil,
    roll: nil,
    chance: nil
  }

  # the events and the loot, see NeuroScav.Raid.Catalog
  @catalog Catalog.compiled()
  @specs @catalog.specs
  @exits @catalog.exits
  @kinds @catalog.kinds
  @searches @catalog.searches
  @camps @catalog.camps
  # a search: the first look's danger (%), and what each next one adds
  @search_danger 10
  @search_step 15
  # a member acts on their own when a choice's quirk roll is within it
  @quirk_chance 25
  # how much a chatterbox eases a talk with scavs or hardens hiding
  @chatter 15
  @bosses @catalog.bosses
  @trophies @catalog.trophies
  @weights @catalog.weights
  @gnomes @catalog.gnomes
  @deadly @catalog.deadly
  # {event, the stat checked} => how the scavs take it
  @karma @catalog.karma
  @scav_events @catalog.scav_events
  # {event, outcome} => {the event it brings, how many events later}
  @chains @catalog.chains
  # what a stall may bring, see new/3
  @detours @catalog.detours
  @spares 5
  @loot @catalog.loot
  @loot_weights @catalog.loot_weights
  # {event, stat} => who makes that check, :best unless listed
  @modes @catalog.modes
  # the consumable that spares a member a wound
  @wound_saver @catalog.savers.wound
  @weathers @catalog.weathers
  @daytimes @catalog.daytimes
  # a time of day lasts this many turns
  @daytime_turns 3

  @karma_limit 3
  @karma_step 5

  # a search's look, as an option: luck isn't checked, a box comes or a wound
  @search {:luck, 0, :found, :wound}
  # retreats in a row a squad may make: then it has to take a risk
  @retreat_limit 1
  # an option with no check: a safe one, a key, a condition or leaving a search
  @no_check %{
    stat: nil,
    member: nil,
    chance: nil,
    reward: nil,
    risk: nil,
    key: nil,
    pay: false,
    price: nil,
    trust: nil,
    mode: nil,
    search: nil,
    leave: false,
    camp: nil,
    retreat: false,
    locked: false
  }

  defdelegate steps, to: Chart
  defdelegate locations, to: Chart
  defdelegate random_map(location \\ nil), to: Chart
  defdelegate card(member), to: Squad
  defdelegate traits, to: Squad
  defdelegate trait(name), to: Squad
  defdelegate stat_step, to: Squad
  defdelegate alive(raid), to: Squad
  defdelegate bleeding?(member), to: Squad
  defdelegate loot_bonuses(raid, member), to: Squad
  defdelegate active?(raid, entry), to: Squad

  @doc "How many retreats in a row a squad may make before it has to take a risk."
  @spec retreat_limit() :: pos_integer()
  def retreat_limit, do: @retreat_limit

  @doc "Every event."
  @spec events() :: [atom()]
  def events, do: Map.keys(@specs)

  @doc "The sets the squad collects: each adds to every stat, see `NeuroScav.Raid.Squad`."
  @spec sets(map()) :: [atom()]
  def sets(raid), do: Squad.sets(raid.squad)

  @doc "Whether an event is a boss."
  @spec boss?(atom()) :: boolean()
  def boss?(event), do: event in @bosses

  @doc "Whether a member may be lost at an event."
  @spec deadly?(atom()) :: boolean()
  def deadly?(event), do: event in @deadly

  @doc "Whether an event is a gnome's: they're after the squad's loot."
  @spec gnome?(atom()) :: boolean()
  def gnome?(event), do: event in @gnomes

  @doc "Whether an event is an exit: through it the raid is over."
  @spec exit?(atom()) :: boolean()
  def exit?(event), do: event in @exits

  @doc """
  What kind of event it is, as the map tells before the squad gets there:
  `:boss`, `:exit`, `:camp`, `:search`, `:gnome`, `:scav`, `:rare` (it may promote),
  `:loot`, `:fight` (it may kill) or `:hazard`.
  """
  @spec kind(atom()) :: atom()
  def kind(event), do: Map.fetch!(@kinds, event)

  @doc "Whether an event is a search: one more box till the squad leaves."
  @spec search?(atom()) :: boolean()
  def search?(event), do: event in @searches

  @doc "Whether an event is a camp: a breather, see the moduledoc."
  @spec camp?(atom()) :: boolean()
  def camp?(event), do: event in @camps

  @doc "Whether an event is the scavs': karma eases its luck checks."
  @spec scav?(atom()) :: boolean()
  def scav?(event), do: event in @scav_events

  @doc "The loot beating a boss brings, nil for any other event."
  @spec trophy(atom()) :: atom() | nil
  def trophy(event), do: @trophies[event]

  @doc "Whether a piece of loot is a boss's trophy."
  @spec trophy_item?(atom()) :: boolean()
  def trophy_item?(item), do: item in Map.values(@trophies)

  @doc """
  The world the squad is in now: the `daytime` and the `weather`, with what
  each adds to checks (`daytime_kinds`, by the kind of check: `:fight`,
  `:search`, `:hide`; `weather_stats`, by stat).
  """
  @spec world(map()) :: %{
          daytime: atom(),
          weather: atom(),
          daytime_kinds: %{atom() => integer()},
          weather_stats: %{atom() => integer()}
        }
  def world(raid) do
    {daytime, kinds} =
      Enum.at(
        @daytimes,
        rem(raid.daytime_start + div(raid.turn, @daytime_turns), length(@daytimes))
      )

    %{
      daytime: daytime,
      weather: raid.weather,
      daytime_kinds: kinds,
      weather_stats: @weathers[raid.weather].stats
    }
  end

  @doc "The location a raid's map is, nil for a map of a test's own."
  @spec location(map()) :: atom() | nil
  def location(raid), do: Map.get(raid.map, :location)

  @doc "A random find, drawn by weight like a route: the valuables are rare, trophies never."
  @spec random_item() :: atom()
  def random_item, do: hd(Chart.draw(Enum.reject(loot(), &trophy_item?/1), @loot_weights, 1))

  @doc "Every kind of loot, for picking a find."
  @spec loot() :: [atom()]
  def loot, do: Map.keys(@loot)

  @doc "Stats a piece of loot adds to the squad's checks."
  @spec loot_bonus(atom()) :: %{atom() => pos_integer()}
  def loot_bonus(item), do: Map.fetch!(@loot, item)

  @doc """
  A new raid for `members` (maps with `:name` and `:rarity`) across `map`, a
  `random_map/0` by default; a list of events is a plain route, a node a
  layer. With one node to start from the squad is there at once. Members are
  told apart by `:index`, names may repeat. `world` pins the weather and the
  time of day the raid starts at (`%{weather: :fog, daytime: :night}`), by
  default the weather is drawn by weight and the time of day at random.
  """
  @spec new([map()], map() | [atom()], map() | nil) :: map()
  def new(members, map \\ random_map(), world \\ nil) do
    map = if is_list(map), do: Chart.linear(map), else: map
    world = world || %{weather: draw_weather(), daytime: Enum.random(Keyword.keys(@daytimes))}

    raid = %{
      squad: Squad.new(members),
      map: map,
      # the nodes the squad has been at, the latest (where it is) first
      path: [],
      # the event at hand, nil once done there (or before the squad is in)
      facing: nil,
      # chain events after the squad: {event, nodes till it catches up}
      pursuers: [],
      # the nodes the squad has seen, at least by kind: it remembers them
      seen: MapSet.new(),
      weather: world.weather,
      daytime_start:
        Enum.find_index(@daytimes, fn {daytime, _kinds} -> daytime == world.daytime end),
      # the events a stall brings, in turn
      spares: Chart.draw(@detours -- Map.values(map.nodes), @weights, @spares),
      turn: 0,
      searched: 0,
      stash: [],
      karma: 0,
      retreats: 0,
      last: nil
    }

    case Chart.starts(map) do
      [start] -> arrive(raid, start)
      _starts -> remember(raid)
    end
  end

  defp draw_weather do
    weights = Map.new(@weathers, fn {weather, %{weight: weight}} -> {weather, weight} end)
    hd(Chart.draw(Map.keys(@weathers), weights, 1))
  end

  @doc """
  The event the squad faces, nil while it picks where to go and once the
  raid is over.
  """
  @spec event(map()) :: atom() | nil
  def event(raid), do: if(over?(raid), do: nil, else: raid.facing)

  @doc "Over once the squad is done at a node with no way on (an exit), or nobody is left."
  @spec over?(map()) :: boolean()
  def over?(raid) do
    alive(raid) == [] or
      (raid.facing == nil and raid.path != [] and raid.map.links[at(raid)] == [])
  end

  @doc "The node the squad is at, nil before it's in."
  @spec at(map()) :: tuple() | nil
  def at(raid), do: List.first(raid.path)

  @doc "The layer the squad is at (0 before it's in), of `Chart.layers/1`."
  @spec layer(map()) :: non_neg_integer()
  def layer(raid), do: if(at = at(raid), do: elem(at, 0), else: 0)

  @doc """
  The nodes the squad may go to now: the next layer's linked to where it
  stands, the first layer's before it's in; none while it faces an event.
  """
  @spec next_nodes(map()) :: [tuple()]
  def next_nodes(raid), do: if(raid.facing || over?(raid), do: [], else: ahead(raid))

  defp ahead(%{path: []} = raid), do: Chart.starts(raid.map)
  defp ahead(raid), do: raid.map.links[at(raid)]

  @doc "The squad goes to node `id`; a node it can't go to now changes nothing."
  @spec move(map(), tuple()) :: map()
  def move(raid, id), do: if(id in next_nodes(raid), do: arrive(raid, id), else: raid)

  # every pursuer comes a node nearer
  defp arrive(raid, id) do
    pursuers = for {event, left} <- raid.pursuers, do: {event, left - 1}
    %{raid | path: [id | raid.path], pursuers: pursuers} |> face() |> remember()
  end

  # what the squad faces where it stands: a pursuer that caught up, otherwise
  # the node's own event
  defp face(raid) do
    case Enum.split_with(raid.pursuers, fn {_event, left} -> left <= 0 end) do
      {[{event, _left} | due], later} -> %{raid | facing: event, pursuers: due ++ later}
      {[], _later} -> %{raid | facing: raid.map.nodes[at(raid)]}
    end
  end

  @doc """
  What the squad can tell of a node: `:event` for where it's been, where it
  may go next and the exits; `:kind` (`kind/1`) for the rest. In the dark
  (`dark?/1`) the rest is `:remembered` (by kind) if the squad has seen it
  before, `:hidden` if not, except a boss and a camp (its fire shows).
  """
  @spec sight(map(), tuple()) :: :event | :kind | :remembered | :hidden
  def sight(raid, id) do
    event = raid.map.nodes[id]

    cond do
      id in raid.path or id in ahead(raid) or exit?(event) -> :event
      boss?(event) or camp?(event) or not dark?(raid) -> :kind
      id in raid.seen -> :remembered
      true -> :hidden
    end
  end

  # what the squad sees now it knows from then on, if only by its kind
  defp remember(raid) do
    seen = for id <- Map.keys(raid.map.nodes), sight(raid, id) != :hidden, into: raid.seen, do: id
    %{raid | seen: seen}
  end

  @doc "Whether the squad sees little of the map: at night or in the fog."
  @spec dark?(map()) :: boolean()
  def dark?(raid), do: world(raid).daytime == :night or raid.weather == :fog

  @doc """
  The nodes the squad can still get to, from where it stands (that one too);
  all of them before it's in.
  """
  @spec reachable(map()) :: MapSet.t()
  def reachable(%{path: []} = raid), do: MapSet.new(Map.keys(raid.map.nodes))
  def reachable(raid), do: Chart.reachable(raid.map, at(raid))

  @doc """
  The current event's options: `%{stat: nil}` for a safe one, otherwise the
  stat, who makes the check (`mode`: `:best`, `:weakest`, `:each`) and the
  `member` who'd do it (for each, the worst at it), the chance in percent and
  what a success brings (`reward`) and a failure costs (`risk`). A key has
  the item in `key`, the member who has it and a sure chance, or is `locked`
  with nobody to have it. A payment (`pay: true`) has the item it takes in
  `price` and its finder, locked with nothing to pay; the scavs' trust has
  the karma it needs in `trust`, locked below it; both are sure. A `retreat`
  is `locked` once the squad has retreated `@retreat_limit` times in a row. A
  search has two: one more look (`search`, the looks so far) by the luckiest
  member, and leaving (`leave: true`). A camp has its three rests (`camp`:
  `:heal`, `:train`, `:repack`), sure, with the `member` (and `stat`) they're
  for.
  """
  @spec options(map()) :: [map()]
  def options(raid) do
    event = event(raid)

    cond do
      search?(event) ->
        %{member: member, chance: chance} = search_plan(raid)

        [
          %{
            @no_check
            | search: raid.searched,
              member: member,
              chance: chance,
              reward: :loot,
              risk: :wound
          },
          %{@no_check | leave: true}
        ]

      camp?(event) ->
        camp_options(raid)

      true ->
        for option <- options_of(event) do
          %{
            option(raid, event, option)
            | retreat: retreat?(option),
              locked: locked?(raid, event, option)
          }
        end
    end
  end

  # a camp's rests: patching up the most wounded, training the weak spot, repacking
  defp camp_options(raid) do
    wounded = Squad.most_wounded(raid)
    {trainee, stat} = Squad.weak_spot(raid)

    [
      %{@no_check | camp: :heal, member: wounded, chance: 100, locked: wounded == nil},
      %{@no_check | camp: :train, member: trainee, stat: stat, chance: 100, reward: :train},
      %{@no_check | camp: :repack, chance: 100, locked: Squad.repack(raid).stash == raid.stash}
    ]
  end

  defp option(_raid, _event, :safe), do: @no_check

  defp option(raid, _event, {:key, item, success}) do
    holder = Squad.holder(raid, item)
    %{@no_check | key: item, member: holder, chance: holder && 100, reward: success}
  end

  # the stash's last active item pays, its finder hands it over
  defp option(raid, _event, :pay) do
    payment = %{@no_check | pay: true, reward: :pass, risk: :drop}

    case Squad.last_active(raid) do
      nil ->
        payment

      index ->
        %{item: item, owner: owner} = Enum.at(raid.stash, index)
        %{payment | price: item, member: Enum.at(raid.squad, owner), chance: 100}
    end
  end

  defp option(raid, _event, {:karma, level}),
    do: %{@no_check | trust: level, chance: if(raid.karma >= level, do: 100), reward: :pass}

  defp option(raid, event, {stat, _difficulty, success, failure} = option) do
    %{member: member, chance: chance} = plan(raid, event, option)

    %{
      @no_check
      | stat: stat,
        mode: mode(event, stat),
        member: member,
        chance: chance,
        reward: success,
        risk: failure
    }
  end

  defp mode(event, stat), do: Map.get(@modes, {event, stat}, :best)

  # the check an option makes: who makes it (by its mode unless given), the
  # chance, and the quirk when a member acted on their own
  defp plan(raid, event, option, member \\ nil) do
    member = member || performer(raid, event, option, alive(raid))
    %{option: option, member: member, chance: chance(raid, event, option, member), quirk: nil}
  end

  # the one of `members` to make a check: the best at it, or the worst
  defp performer(raid, event, {stat, _difficulty, _success, _failure} = option, members) do
    by_chance = &chance(raid, event, option, &1)

    if mode(event, stat) == :best,
      do: Enum.max_by(members, by_chance),
      else: Enum.min_by(members, by_chance)
  end

  # A search's look, by the luckiest unless given: a box found or a wound on
  # luck, the danger growing with every look; the time of day eases it or not.
  defp search_plan(raid, member \\ nil) do
    member = member || Enum.max_by(alive(raid), &Squad.with_loot(raid, &1, :luck))
    daytime = Map.get(world(raid).daytime_kinds, :search, 0)
    chance = 100 - @search_danger - @search_step * raid.searched + daytime
    %{option: @search, member: member, chance: chance |> max(5) |> min(95), quirk: nil}
  end

  # a member's chance at a check: their stat with their loot, minus the
  # difficulty, eased or made harder by karma and the world, within 5..95%
  defp chance(raid, event, {stat, difficulty, _success, _failure} = option, member) do
    world = world(raid)

    ease =
      karma_ease(raid, event, stat) + Map.get(world.weather_stats, stat, 0) +
        Map.get(world.daytime_kinds, kind(event, option), 0)

    (Squad.with_loot(raid, member, stat) + ease - difficulty) |> max(5) |> min(95)
  end

  # what kind of check it is, for the time of day: a fight, a search, hiding or none
  defp kind(_event, {:strength, _difficulty, _success, _failure}), do: :fight
  defp kind(_event, {_stat, _difficulty, :trophy, _failure}), do: :fight
  defp kind(_event, {_stat, _difficulty, :loot, _failure}), do: :search

  defp kind(event, {stat, _difficulty, _success, _failure} = option) do
    if retreat?(option) or Map.get(@modes, {event, stat}) == :weakest, do: :hide
  end

  # A key nobody has is locked, so is a payment with nothing to pay and trust
  # the scavs don't give; and a retreat once the squad has retreated as long as
  # it may, unless the event has nothing else to take or it's an exit.
  defp locked?(raid, _event, {:key, item, _success}), do: Squad.holder(raid, item) == nil
  defp locked?(raid, _event, :pay), do: Squad.last_active(raid) == nil
  defp locked?(raid, _event, {:karma, level}), do: raid.karma < level

  defp locked?(raid, event, option) do
    raid.retreats >= @retreat_limit and retreat?(option) and not exit?(event) and
      Enum.any?(options_of(event), &(not retreat?(&1) and not locked?(raid, event, &1)))
  end

  # the safe option, or an escape: a check that only lets the squad by and can't kill
  defp retreat?(:safe), do: true
  defp retreat?({_stat, _difficulty, :pass, failure}), do: failure != :lose
  defp retreat?(_option), do: false

  # talking to scavs (a luck check at a scav event) goes as the squad's karma
  defp karma_ease(raid, event, :luck) when event in @scav_events, do: raid.karma * @karma_step
  defp karma_ease(_raid, _event, _stat), do: 0

  @doc """
  Takes option `index` of the current event: a check succeeds when `roll`
  (1..100) is within its chance; the loot found is `item`. A member acts on
  their own when `quirk` (1..100) is within `@quirk_chance`: by default
  nobody does, so a raid stays predictable. `last` (`t:last/0`) holds what
  happened, for the page to tell. A locked option changes nothing.
  """
  @spec choose(map(), non_neg_integer(), 1..100, atom(), 1..100) :: map()
  def choose(raid, index, roll, item \\ random_item(), quirk \\ 100) do
    event = event(raid)
    quirky = quirk <= @quirk_chance

    case event && pick(raid, event, index) do
      nil ->
        raid

      picked ->
        case quirky && takeover(raid, event, picked) do
          %{} = plan -> check(raid, event, plan, roll, item, false)
          _none -> act(raid, event, picked, roll, item, quirky)
        end
    end
  end

  defp act(raid, event, :safe, _roll, _item, _quirky),
    do: step(raid, %{@last | event: event, outcome: :safe, retreat: true})

  defp act(raid, event, :pay, _roll, _item, _quirky) do
    {paid, stash} = List.pop_at(raid.stash, Squad.last_active(raid))
    owner = Enum.at(raid.squad, paid.owner)

    step(%{raid | stash: stash}, %{
      @last
      | event: event,
        outcome: :paid,
        item: paid.item,
        member: owner.name,
        index: owner.index,
        retreat: false
    })
  end

  defp act(raid, event, {:karma, _level}, _roll, _item, _quirky),
    do: step(raid, %{@last | event: event, outcome: :trusted, retreat: false})

  defp act(raid, event, :leave, _roll, _item, _quirky),
    do: step(raid, %{@last | event: event, outcome: :left})

  defp act(raid, event, :search, roll, item, quirky),
    do: check(raid, event, search_plan(raid), roll, item, quirky)

  defp act(raid, event, {:camp, :heal}, _roll, _item, _quirky) do
    patched = Squad.most_wounded(raid)

    raid
    |> Squad.update_member(patched.index, &%{&1 | wounds: 0})
    |> step(%{@last | event: event, outcome: :heal, member: patched.name, index: patched.index})
  end

  defp act(raid, event, {:camp, :train}, _roll, _item, _quirky) do
    {trainee, stat} = Squad.weak_spot(raid)

    raid
    |> Squad.train(trainee.index, stat)
    |> step(%{
      @last
      | event: event,
        outcome: :train,
        member: trainee.name,
        index: trainee.index,
        stat: stat
    })
  end

  defp act(raid, event, {:camp, :repack}, _roll, _item, _quirky),
    do: raid |> Squad.repack() |> step(%{@last | event: event, outcome: :repacked})

  defp act(raid, event, {:key, key, success}, _roll, item, _quirky) do
    holder = Squad.holder(raid, key)

    settle(raid, success, holder, item, %{
      @last
      | event: event,
        outcome: success,
        member: holder.name,
        index: holder.index,
        retreat: false,
        used: key
    })
  end

  defp act(raid, event, {stat, _difficulty, _success, _failure} = option, roll, item, quirky) do
    cond do
      mode(event, stat) == :each ->
        check_each(raid, event, option, roll)

      quirky ->
        check(raid, event, twist(raid, event, plan(raid, event, option)), roll, item, true)

      true ->
        check(raid, event, plan(raid, event, option), roll, item, false)
    end
  end

  # the first alive member with the trait, nil when there's none
  defp quirky(raid, trait), do: Enum.find(alive(raid), &(&1.trait == trait))

  # A greedy one goes for the loot (one more box rather than leaving, too), a
  # psycho for the fight, whatever the squad chose: the check they make instead.
  defp takeover(raid, _event, :leave) do
    if greedy = quirky(raid, :greedy),
      do: %{search_plan(raid, greedy) | quirk: {:greedy, greedy.name}}
  end

  defp takeover(raid, event, picked) do
    Enum.find_value(
      [
        greedy: &match?({_stat, _difficulty, :loot, _failure}, &1),
        psycho: &match?({:strength, _, _, _}, &1)
      ],
      fn {trait, target?} ->
        member = quirky(raid, trait)

        option =
          Enum.find(options_of(event), &(target?.(&1) and not locked?(raid, event, &1)))

        if member && option && option != picked,
          do: %{plan(raid, event, option, member) | quirk: {trait, member.name}}
      end
    )
  end

  # what a member does on their own at a check, if anything
  defp twist(raid, event, plan),
    do: coward(raid, event, plan) || chatter(raid, event, plan) || plan

  # a coward leaves a deadly check to the next best one
  defp coward(raid, event, %{option: {stat, _difficulty, _success, failure} = option} = plan) do
    coward = plan.member
    others = Enum.reject(alive(raid), &(&1.index == coward.index))

    if coward.trait == :coward and failure == :lose and others != [] and
         mode(event, stat) == :best,
       do: %{
         plan(raid, event, option, performer(raid, event, option, others))
         | quirk: {:coward, coward.name}
       }
  end

  # a chatterbox talks scavs round (a luck check at their event) or gives the
  # squad away when it hides
  defp chatter(raid, event, %{option: {stat, _difficulty, _success, _failure} = option} = plan) do
    chatty = quirky(raid, :chatty)

    cond do
      chatty == nil ->
        nil

      stat == :luck and scav?(event) ->
        %{plan | chance: min(plan.chance + @chatter, 95), quirk: {:chatty_scav, chatty.name}}

      kind(event, option) == :hide ->
        %{plan | chance: max(plan.chance - @chatter, 5), quirk: {:chatty, chatty.name}}

      true ->
        nil
    end
  end

  # option `index` of an event: one more look or leaving at a search, otherwise as listed
  defp pick(_raid, event, index) when event in @searches, do: Enum.at([:search, :leave], index)

  defp pick(raid, event, index) when event in @camps do
    option = Enum.at(camp_options(raid), index)
    if option && not option.locked, do: {:camp, option.camp}
  end

  defp pick(raid, event, index) do
    option = Enum.at(options_of(event), index)
    if option && not locked?(raid, event, option), do: option
  end

  # an event's options as listed, none when there's no event
  defp options_of(event), do: get_in(@specs, [event, :options]) || []

  # A check succeeds when the roll is within the chance; a lucky one's failed
  # one comes off after all when nobody else acted on their own (`lucky`).
  defp check(raid, event, %{option: option, member: member} = plan, roll, item, lucky) do
    {stat, _difficulty, success, failure} = option
    lucky = lucky and plan.quirk == nil and member.trait == :lucky and roll > plan.chance
    outcome = if roll <= plan.chance or lucky, do: success, else: failure

    settle(raid, outcome, member, item, %{
      @last
      | event: event,
        stat: stat,
        retreat: retreat?(option),
        outcome: outcome,
        member: member.name,
        index: member.index,
        quirk: if(lucky, do: {:lucky, member.name}, else: plan.quirk),
        roll: roll,
        chance: plan.chance
    })
  end

  # one roll against everyone's chance: the ones it beats are wounded (the
  # catalog has an each check pass or wound)
  defp check_each(raid, event, {stat, _difficulty, _success, _failure} = option, roll) do
    last = %{@last | event: event, stat: stat, retreat: retreat?(option), roll: roll}

    case for member <- alive(raid), roll > chance(raid, event, option, member), do: member do
      [] ->
        step(raid, %{last | outcome: :pass})

      beaten ->
        {raid, used} =
          Enum.reduce(beaten, {raid, nil}, fn member, {raid, used} ->
            {raid, spent} = Squad.hurt(raid, member, :wound, last.stat)
            {raid, used || spent}
          end)

        step(raid, %{
          last
          | outcome: if(match?([_], beaten), do: :wound, else: :wounds),
            member: Enum.map_join(beaten, ", ", & &1.name),
            index: hd(beaten).index,
            used: used
        })
    end
  end

  defp settle(raid, :lose, member, _item, last) do
    case Squad.hurt(raid, member, :lose, last.stat) do
      {raid, nil} -> step(raid, last)
      {raid, used} -> step(raid, %{last | outcome: :wound, used: used})
    end
  end

  # a look at a search finds loot like any other
  defp settle(raid, found, member, item, last) when found in [:loot, :found],
    do:
      step(%{raid | stash: raid.stash ++ [%{item: item, owner: member.index}]}, %{
        last
        | item: item
      })

  # the last active item goes: a fallen member's loot is no use to give away;
  # an empty stash has nothing to give
  defp settle(raid, :drop, _member, _item, last) do
    case Squad.last_active(raid) do
      nil ->
        step(raid, last)

      index ->
        {dropped, stash} = List.pop_at(raid.stash, index)
        step(%{raid | stash: stash}, %{last | item: dropped.item})
    end
  end

  defp settle(raid, :revive, _member, _item, last) do
    cond do
      fallen = Enum.find(raid.squad, &(not &1.alive)) ->
        raid
        |> Squad.set_alive(fallen.index, true)
        |> step(%{last | member: fallen.name, index: fallen.index})

      # nobody to bring back: the most wounded one is patched up
      patched = Squad.most_wounded(raid) ->
        raid
        |> Squad.update_member(patched.index, &%{&1 | wounds: 0})
        |> step(%{last | outcome: :heal, member: patched.name, index: patched.index})

      true ->
        step(raid, %{last | outcome: :pass})
    end
  end

  defp settle(raid, :train, member, _item, last),
    do: raid |> Squad.train(member.index, last.stat) |> step(last)

  # propital takes the wound away; a medkit turns the third into one that
  # can't kill; with neither the third kills
  defp settle(raid, :wound, member, _item, last) do
    case Squad.hurt(raid, member, :wound, last.stat) do
      {raid, @wound_saver} ->
        step(raid, %{last | outcome: :spared, used: @wound_saver})

      {raid, nil} ->
        outcome = if Enum.at(raid.squad, member.index).alive, do: :wound, else: :lose
        step(raid, %{last | outcome: outcome})

      {raid, used} ->
        step(raid, %{last | used: used})
    end
  end

  defp settle(raid, :promote, member, _item, last) do
    last = if Squad.next_rarity(member.rarity), do: last, else: %{last | outcome: :train}
    raid |> Squad.rank_up(member, last.stat) |> step(last)
  end

  defp settle(raid, :trophy, member, _item, last) do
    trophy = trophy(last.event)

    %{raid | stash: raid.stash ++ [%{item: trophy, owner: member.index}]}
    |> Squad.rank_up(member, last.stat)
    |> step(%{last | item: trophy})
  end

  # the squad stays where it is, and meets a spare event there instead (step/2 doesn't move it on)
  defp settle(raid, :stall, _member, _item, last) do
    case raid.spares do
      [spare | spares] ->
        raid = put_in(raid, [:map, :nodes, at(raid)], spare)
        step(%{raid | facing: spare, spares: spares}, last)

      [] ->
        step(raid, last)
    end
  end

  defp settle(raid, _pass_or_nothing, _member, _item, last), do: step(raid, last)

  defp step(raid, last) do
    {follow_up, pursuers} = follow(raid, Map.get(@chains, {last.event, last.outcome}))

    karma =
      (raid.karma + Map.get(@karma, {last.event, last.stat}, 0))
      |> max(-@karma_limit)
      |> min(@karma_limit)

    raid = %{
      raid
      | squad: Enum.map(raid.squad, &Squad.bleed/1),
        pursuers: pursuers,
        turn: raid.turn + 1,
        searched: if(last.outcome == :found, do: raid.searched + 1, else: 0),
        karma: karma,
        retreats: retreats(raid.retreats, last.retreat),
        last: %{last | follow_up: follow_up, karma: karma - raid.karma}
    }

    # a stall keeps the squad at the event at hand, so does a look at a search
    remember(if last.outcome in [:stall, :found], do: raid, else: done(raid))
  end

  # The event at hand is done: after a pursuer comes the next one or the
  # node's own event; with that done the squad goes on by itself where
  # there's one way only.
  defp done(raid) do
    at = at(raid)

    if raid.facing != raid.map.nodes[at] do
      face(raid)
    else
      case raid.map.links[at] do
        [next] -> arrive(%{raid | facing: nil}, next)
        _none_or_more -> %{raid | facing: nil}
      end
    end
  end

  # retreats in a row: a retreat counts up, a risk taken ends them, leaving a
  # search (nil) is neither
  defp retreats(count, true), do: count + 1
  defp retreats(count, nil), do: count
  defp retreats(_count, false), do: 0

  # a chain's event catches up `delay` nodes later, at the last node at the
  # latest: on the last one the raid ends, so its event starts no chain
  defp follow(raid, {event, delay}) do
    left = Chart.layers(raid.map) - 1 - layer(raid)

    if left > 0,
      do: {event, raid.pursuers ++ [{event, min(delay, left)}]},
      else: {nil, raid.pursuers}
  end

  defp follow(raid, nil), do: {nil, raid.pursuers}
end
