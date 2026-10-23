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
    member's checked stat grows by `stat_step/0`) or `:promote` (the member's
    rarity goes one up, the stats grow by the difference of rarity bonuses;
    at the top it's a `:train`)
  - failure: `:lose` (the member doesn't make it out), `:wound` (the checked
    stat drops by `stat_step/0`, to 1 at least), `:drop` (the last active
    item of the stash is gone) or `:nothing`

  Routes pick events by weight: the promoting ones are rare.

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
    tower: [{:agility, 5, :train, :lose}, :safe]
  }

  # how often an event comes up on a route, 1 unless listed
  @weights %{veteran: 0.12, lightkeeper: 0.12}

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
    nvg: %{agility: 5, luck: 5}
  }

  # how often a kind of loot turns up, 1 unless listed: the valuables are rare
  @loot_weights %{ledx: 0.3, keycard: 0.3, slick: 0.5}

  @steps 10..13

  @doc "How many events a raid goes through, picked for each raid."
  @spec steps() :: Range.t()
  def steps, do: @steps

  @doc "Every event."
  @spec events() :: [atom()]
  def events, do: Map.keys(@events)

  @doc "How much a member's stat grows or drops on `:train` and `:wound`."
  @spec stat_step() :: pos_integer()
  def stat_step, do: @stat_step

  @doc """
  A random route: as many different events as `steps/0` picks, drawn by
  weight (keys `u^(1/weight)`, the largest win), so rare events seldom show up.
  """
  @spec route() :: [atom()]
  def route, do: draw(events(), @weights, Enum.random(@steps))

  @doc "A random find, drawn by weight like a route: the valuables are rare."
  @spec random_item() :: atom()
  def random_item, do: hd(draw(loot(), @loot_weights, 1))

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
  may repeat.
  """
  @spec new([map()], [atom()]) :: map()
  def new(members, route \\ route()) do
    squad =
      members
      |> Enum.with_index()
      |> Enum.map(fn {member, index} ->
        member |> card() |> Map.merge(%{index: index, alive: true})
      end)

    %{
      squad: squad,
      route: route,
      step: 0,
      stash: [],
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
  brings (`reward`) and a failure costs (`risk`).
  """
  @spec options(map()) :: [map()]
  def options(raid) do
    raid |> event() |> then(&Map.get(@events, &1, [])) |> Enum.map(&option(raid, &1))
  end

  defp option(_raid, :safe), do: %{stat: nil, member: nil, chance: nil, reward: nil, risk: nil}

  defp option(raid, {stat, difficulty, success, failure}) do
    member = raid |> alive() |> Enum.max_by(&with_loot(raid, &1, stat))
    chance = (with_loot(raid, member, stat) - difficulty) |> max(5) |> min(95)
    %{stat: stat, member: member, chance: chance, reward: success, risk: failure}
  end

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

    case event && Enum.at(Map.fetch!(@events, event), index) do
      nil ->
        raid

      :safe ->
        step(raid, %{event: event, outcome: :safe, member: nil, index: nil, item: nil, stat: nil})

      option ->
        check(raid, event, option, roll, item)
    end
  end

  defp check(raid, event, {stat, _difficulty, success, failure} = option, roll, item) do
    %{member: member, chance: chance} = option(raid, option)
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

  defp settle(raid, :promote, member, item, last) do
    case next_rarity(member.rarity) do
      nil -> settle(raid, :train, member, item, %{last | outcome: :train})
      rarity -> raid |> promote(member.index, rarity) |> step(last)
    end
  end

  defp settle(raid, _pass_or_nothing, _member, _item, last), do: step(raid, last)

  defp set_alive(raid, index, alive), do: update_member(raid, index, &%{&1 | alive: alive})

  defp add_stat(raid, index, stat, delta),
    do:
      update_member(raid, index, fn member ->
        update_in(member.stats[stat], &max(&1 + delta, 1))
      end)

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

  defp step(raid, last), do: %{raid | step: raid.step + 1, last: last}
end
