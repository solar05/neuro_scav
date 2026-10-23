defmodule NeuroScav.Raid.Squad do
  @moduledoc """
  A raid's squad and stash as `NeuroScav.Raid` keeps them (`squad`,
  `stash`): the members' raid cards and traits, the loot that works for its
  finder, wounds and bleeding, the consumables that spare a member,
  promotions. The functions take a raid and return it changed.

  A member's raid card is the battle card (`BattleRoom.card/1`) with the part
  that comes from the name cut to `@base_share` percent (1 at least), the
  rarity bonus kept whole. Wounds add up: from the second one a member
  bleeds (`bleeding?/1`), losing `@bleed` of every stat at every step, the
  third kills. The squad's consumables spend themselves on what they spare a
  member from: propital takes a wound away, a medkit turns a death, the third
  wound's too, into a wound that can't kill.
  """

  alias NeuroScav.BattleRoom
  alias NeuroScav.Raid.Catalog

  @catalog Catalog.compiled()
  @loot @catalog.loot
  @traits @catalog.traits
  # the consumables sparing a member a wound, a death
  @wound_saver @catalog.savers.wound
  @death_saver @catalog.savers.lose

  @rarities [:common, :uncommon, :rare, :epic, :legendary]
  @stat_step 10
  # the share (%) of a battle card's name part a raid stat keeps: with whole
  # cards the best of five passes nearly every check
  @base_share 60
  # from this wound on a member bleeds, losing @bleed of every stat at every
  # step; @deadly_wound kills
  @bleeding_at 2
  @deadly_wound 3
  @bleed 3

  @doc """
  The squad of `members` (maps with `:name` and `:rarity`): their raid cards,
  told apart by `:index` (names may repeat), alive, unhurt, with their trait.
  """
  @spec new([map()]) :: [map()]
  def new(members) do
    members
    |> Enum.with_index()
    |> Enum.map(fn {member, index} ->
      member
      |> card()
      |> Map.merge(%{index: index, alive: true, wounds: 0, trait: trait(member.name)})
    end)
  end

  @doc "A member's raid card, see the moduledoc; the gnome stays a joker."
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

  @doc "Every trait a member may have, see `trait/1`."
  @spec traits() :: [atom()]
  def traits, do: @traits

  @doc "A member's trait: what they may do on their own, the same for a name every time."
  @spec trait(String.t()) :: atom()
  def trait(name), do: Enum.at(@traits, :erlang.phash2({name, :trait}, length(@traits)))

  @doc "How much a member's stat grows or drops on a training and a wound."
  @spec stat_step() :: pos_integer()
  def stat_step, do: @stat_step

  @doc "Members still alive."
  @spec alive(map()) :: [map()]
  def alive(raid), do: Enum.filter(raid.squad, & &1.alive)

  @doc "Whether a member bleeds: wounded enough to lose a little of every stat at every step."
  @spec bleeding?(map()) :: boolean()
  def bleeding?(member), do: member.wounds >= @bleeding_at

  @doc "A bleeding member loses a little of every stat at a step, to 1 at least."
  @spec bleed(map()) :: map()
  def bleed(%{alive: true} = member) do
    if bleeding?(member),
      do: %{
        member
        | stats: Map.new(member.stats, fn {stat, value} -> {stat, max(value - @bleed, 1)} end)
      },
      else: member
  end

  def bleed(member), do: member

  @doc "The alive member who has the item, nil when nobody does."
  @spec holder(map(), atom()) :: map() | nil
  def holder(raid, item) do
    Enum.find_value(raid.stash, fn entry ->
      member = Enum.at(raid.squad, entry.owner)
      if entry.item == item and member.alive, do: member
    end)
  end

  @doc "The index of the stash's last item whose finder is alive, nil when there's none."
  @spec last_active(map()) :: non_neg_integer() | nil
  def last_active(raid) do
    List.last(for {entry, index} <- Enum.with_index(raid.stash), active?(raid, entry), do: index)
  end

  @doc "A member's stat with the bonuses of the loot they found."
  @spec with_loot(map(), map(), atom()) :: integer()
  def with_loot(raid, member, stat),
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
  What a failure (`:lose` or `:wound`, of `stat`) does to a member, and the
  consumable that spared them, if any: propital takes a wound away, a medkit
  turns a death (the third wound's too) into a wound that can't kill; the
  third wound kills.
  """
  @spec hurt(map(), map(), :lose | :wound, atom()) :: {map(), atom() | nil}
  def hurt(raid, member, failure, stat) do
    wounds = Enum.at(raid.squad, member.index).wounds
    deadly = failure == :lose or wounds + 1 >= @deadly_wound

    cond do
      failure == :wound and has?(raid, @wound_saver) ->
        {spend(raid, @wound_saver), @wound_saver}

      deadly and has?(raid, @death_saver) ->
        raid =
          raid |> spend(@death_saver) |> wound(member, stat, min(wounds + 1, @deadly_wound - 1))

        {raid, @death_saver}

      deadly ->
        {set_alive(raid, member.index, false), nil}

      true ->
        {wound(raid, member, stat, wounds + 1), nil}
    end
  end

  defp wound(raid, member, stat, wounds) do
    raid
    |> add_stat(member.index, stat, -@stat_step)
    |> update_member(member.index, &%{&1 | wounds: wounds})
  end

  # a consumable is the squad's: any alive member's will do, and it's gone once spent
  defp has?(raid, item), do: spare_entry(raid, item) != nil

  defp spend(raid, item), do: %{raid | stash: List.delete_at(raid.stash, spare_entry(raid, item))}

  defp spare_entry(raid, item),
    do: Enum.find_index(raid.stash, &(&1.item == item and active?(raid, &1)))

  @doc "A member is fallen, or back."
  @spec set_alive(map(), non_neg_integer(), boolean()) :: map()
  def set_alive(raid, index, alive), do: update_member(raid, index, &%{&1 | alive: alive})

  @doc "A member's stat grows by `stat_step/0`."
  @spec train(map(), non_neg_integer(), atom()) :: map()
  def train(raid, index, stat), do: add_stat(raid, index, stat, @stat_step)

  defp add_stat(raid, index, stat, delta),
    do:
      update_member(raid, index, fn member ->
        update_in(member.stats[stat], &max(&1 + delta, 1))
      end)

  @doc "A promotion; at the top the checked `stat` is trained instead."
  @spec rank_up(map(), map(), atom()) :: map()
  def rank_up(raid, member, stat) do
    case next_rarity(member.rarity) do
      nil -> train(raid, member.index, stat)
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

  @doc "The rarity one up, nil at the top: a legendary has nowhere to go, the gnome is off the scale."
  @spec next_rarity(atom()) :: atom() | nil
  def next_rarity(rarity) do
    case Enum.find_index(@rarities, &(&1 == rarity)) do
      nil -> nil
      index -> Enum.at(@rarities, index + 1)
    end
  end

  @doc "Changes the member at `index` with `fun`."
  @spec update_member(map(), non_neg_integer(), (map() -> map())) :: map()
  def update_member(raid, index, fun),
    do: update_in(raid.squad, &List.update_at(&1, index, fun))
end
