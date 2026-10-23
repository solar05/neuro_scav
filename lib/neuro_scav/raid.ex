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
    item of the stash is gone), `:nothing` or `:stall` (the squad doesn't get
    by and stays where it is, before another event: see below)

  A stall doesn't move the squad on (`step` stays, `turn` counts every
  choice): where it stands it now meets a spare event instead, one of the
  `spares` drawn when the raid starts (events off the route and the
  crossroads paths that can't stall themselves). With none left it meets the
  same event again.

  Routes pick events by weight: the promoting ones are rare. A route may get
  a boss (`boss?/1`), in the middle or at the end; beating one brings a trophy.

  Some outcomes start a chain: another event (never on a random route) comes
  a few events later, before the last one, so the route grows by one. What
  brought it is in `last.follow_up`.

  At a crossroads (`crossroads?/1`) there's no check: each option is a path,
  an event drawn when the raid starts or given to `new/3` (`forks`), and the
  one taken comes next.

  Scavs remember: some options change the squad's `karma` (within
  ±`@karma_limit`, the change is in `last.karma`), and every point of it
  eases a luck check at a scav event by `@karma_step`, a bad one makes it harder.

  A squad can't run forever: a retreat is the safe option or a check that only
  lets the squad by and can't kill (an escape). After `@retreat_limit` of them
  in a row the retreats are locked (`locked: true` in `options/1`) until the
  squad takes something else, unless an event has nothing else. A crossroads
  path is neither.

  The events and the loot are in `NeuroScav.Raid.Catalog`.

  A raid is plain data: the page keeps it, every step returns a new one. The
  route, the crossroads paths, the spares, the roll (1..100) and the loot
  found may all be given, so a raid is fully predictable in tests.
  """

  alias NeuroScav.BattleRoom
  alias NeuroScav.Raid.Catalog

  @typedoc """
  What the last step did, every key always there, nil where it doesn't apply:
  the `event` and its `outcome`; the `member` (a name) and `index` of the one
  it happened to; the `item` found, dropped or stolen; the `stat` checked;
  the `path` taken at a crossroads; whether it was a `retreat` (nil for a
  path); the event a chain brought (`follow_up`) and the change of `karma`.
  """
  @type last :: %{
          event: atom(),
          outcome: atom(),
          member: String.t() | nil,
          index: non_neg_integer() | nil,
          item: atom() | nil,
          stat: atom() | nil,
          path: atom() | nil,
          retreat: boolean() | nil,
          follow_up: atom() | nil,
          karma: integer()
        }
  @last %{
    event: nil,
    outcome: nil,
    member: nil,
    index: nil,
    item: nil,
    stat: nil,
    path: nil,
    retreat: nil,
    follow_up: nil,
    karma: 0
  }

  # the events and the loot, see NeuroScav.Raid.Catalog
  @catalog Catalog.compiled()
  @specs @catalog.specs
  @crossroads @catalog.crossroads
  @bosses @catalog.bosses
  @trophies @catalog.trophies
  @weights @catalog.weights
  @gnomes @catalog.gnomes
  # {event, the stat checked} => how the scavs take it
  @karma @catalog.karma
  @scav_events @catalog.scav_events
  # {event, outcome} => {the event it brings, how many events later}
  @chains @catalog.chains
  # what a random route or a crossroads path is drawn from
  @common @catalog.common
  # what a stall may bring, see new/3
  @detours @catalog.detours
  @spares 5
  @loot @catalog.loot
  @loot_weights @catalog.loot_weights

  @boss_chance 0.4
  @karma_limit 3
  @karma_step 5

  @rarities [:common, :uncommon, :rare, :epic, :legendary]
  @stat_step 10
  # the share (%) of a battle card's name part a raid stat keeps: with whole
  # cards the best of five passes nearly every check
  @base_share 60

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
  may repeat. Each crossroads on the route gets two paths: `forks` pins them
  (`%{crossroads => [path, path]}`), by default they're drawn, events that
  are on the route nowhere else.
  """
  @spec new([map()], [atom()], %{atom() => [atom()]} | nil) :: map()
  def new(members, route \\ route(), forks \\ nil) do
    squad =
      members
      |> Enum.with_index()
      |> Enum.map(fn {member, index} ->
        member |> card() |> Map.merge(%{index: index, alive: true})
      end)

    forks = forks || draw_forks(route)
    taken = route ++ Enum.concat(Map.values(forks))

    %{
      squad: squad,
      route: route,
      forks: forks,
      # the events a stall brings, in turn
      spares: draw(@detours -- taken, @weights, @spares),
      step: 0,
      turn: 0,
      stash: [],
      karma: 0,
      retreats: 0,
      last: nil
    }
  end

  # two paths for each crossroads on the route, off it and apart from each other
  defp draw_forks(route) do
    for crossroads <- route, crossroads?(crossroads), reduce: %{} do
      forks ->
        taken = route ++ Enum.concat(Map.values(forks))
        Map.put(forks, crossroads, draw(@common -- taken, @weights, 2))
    end
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
  (1..100) is within its chance; the loot found is `item`. `last` (`t:last/0`)
  holds what happened, for the page to tell. A locked option changes nothing.
  """
  @spec choose(map(), non_neg_integer(), 1..100, atom()) :: map()
  def choose(raid, index, roll, item \\ random_item()) do
    event = event(raid)
    safe = %{@last | event: event, outcome: :safe, retreat: true}

    case event && pick(raid, event, index) do
      nil ->
        raid

      {:path, path} ->
        route = List.insert_at(raid.route, raid.step + 1, path)
        step(%{raid | route: route}, %{safe | outcome: :path, path: path, retreat: nil})

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
      @last
      | event: event,
        outcome: outcome,
        member: member.name,
        index: member.index,
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

  # the squad stays where it is, and meets a spare event there (step/2 doesn't move it on)
  defp settle(raid, :stall, _member, _item, last) do
    case raid.spares do
      [spare | spares] ->
        step(%{raid | route: List.replace_at(raid.route, raid.step, spare), spares: spares}, last)

      [] ->
        step(raid, last)
    end
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
        # a stall keeps the squad where it is
        step: if(last.outcome == :stall, do: raid.step, else: raid.step + 1),
        turn: raid.turn + 1,
        karma: karma,
        retreats: retreats(raid.retreats, last.retreat),
        last: %{last | follow_up: follow_up, karma: karma - raid.karma}
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
