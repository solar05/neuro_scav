defmodule NeuroScav.BattleRoom do
  @moduledoc """
  One card battle: two players, one redraw each, a card each (`size: 1`) or a
  team of five (`size: 5`).

  A room is a process per invite link, registered in `NeuroScav.BattleRegistry`
  under `NeuroScav.BattleSupervisor`. The creator is the first player and the
  first other visitor the second; everyone after that only watches. An `open`
  room (`create(owner, open: true)`) is meant for a random opponent rather than
  an invite; the battle LiveView lists it while its owner waits.

  ## Flow

  Each player draws their cards, then either fights with them or redraws all of
  them once — redrawn cards are final, so they are ready right away. When both
  players are ready the cards meet slot by slot and are compared stat by stat:
  every stat of every pair is a round, whoever wins more rounds wins the
  battle. Rematches keep the players and the size and count the battles each
  player won in `wins` (draws count for nobody).

  Every change is broadcast to `battle:<id>` as `{:battle_updated, state}`.
  The state holds both players' cards; LiveViews render only the viewer's own
  cards until the result is in, so nothing leaks to the browser before the reveal.

  ## Bot

  A room created with `create_with_bot/3` seats a bot as the second player. It
  "thinks" for 2–5 seconds at the start of every battle, then takes its turn
  without seeing the opponent's cards: it redraws below-average cards and
  fights with the rest. Bot cards don't count in the statistics and aren't
  announced.

  Rooms live in memory and stop after an hour without activity, broadcasting
  `:battle_closed`.
  """

  use GenServer, restart: :temporary

  alias NeuroScav.{PubSub, ScavengersServer}

  @stats [:strength, :agility, :luck]
  @rarity_bonus %{common: 0, uncommon: 5, rare: 10, epic: 15, legendary: 25}
  # the gnome is a joker: one above the best legendary stat (75 + 25) everywhere
  @joker_stat 101
  @idle_timeout :timer.hours(1)
  @bot "bot"
  @bot_think_ms 2_000..5_000
  # mean card without a rarity bonus: 3 stats × 38 (mean of 1..75)
  @average_total 114
  @team_size ScavengersServer.max_team_members()

  # Client API

  @doc "Battle stats in round order."
  @spec stats() :: [atom()]
  def stats, do: @stats

  @doc "Cards per player in a team battle."
  @spec team_size() :: pos_integer()
  def team_size, do: @team_size

  @doc "Player id of the bot (user ids are UUIDs, so it never clashes)."
  @spec bot() :: String.t()
  def bot, do: @bot

  @doc """
  Opens a room with `owner_id` as the first player. Returns its id for the invite link.

  `open: true` marks it as waiting for any opponent instead of an invited one,
  `size:` is the number of cards per player, 1 (default) or `team_size/0`.
  """
  @spec create(String.t(), keyword()) :: {:ok, String.t()}
  def create(owner_id, opts \\ []), do: start_room(owner_id, nil, opts)

  @doc """
  Opens a room where `owner_id` plays against the bot; the bot draws in `locale`.

  `size:` works as in `create/2`; `think_ms:` sets the range the bot's thinking
  time is picked from (tests pass a long one and trigger the turn with a
  `:bot_turn` message).
  """
  @spec create_with_bot(String.t(), String.t(), keyword()) :: {:ok, String.t()}
  def create_with_bot(owner_id, locale, opts \\ []) do
    bot = %{locale: locale, think_ms: Keyword.get(opts, :think_ms, @bot_think_ms)}
    start_room(owner_id, bot, Keyword.take(opts, [:size]))
  end

  defp start_room(owner_id, bot, opts) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    size = if opts[:size] == @team_size, do: @team_size, else: 1
    room = {__MODULE__, {id, owner_id, bot, %{open: Keyword.get(opts, :open, false), size: size}}}
    {:ok, _pid} = DynamicSupervisor.start_child(NeuroScav.BattleSupervisor, room)
    {:ok, id}
  end

  @doc """
  Takes the second player's seat if it is free; otherwise the user just watches.
  """
  @spec join(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def join(id, user_id), do: call(id, {:join, user_id})

  @doc """
  Draws the player's cards, or redraws them once.
  """
  @spec draw(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def draw(id, user_id, locale), do: call(id, {:draw, user_id, locale})

  @doc """
  Locks in the player's cards; the battle resolves when both are ready.
  """
  @spec ready(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def ready(id, user_id), do: call(id, {:ready, user_id})

  @doc """
  Starts the next battle between the same players once this one is over.
  """
  @spec rematch(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def rematch(id, user_id), do: call(id, {:rematch, user_id})

  @doc """
  Battle card of a scavenger: each stat is 1..75 from a hash of the name plus
  a rarity bonus, so the same name always gets the same card. The gnome beats
  every other card in every stat.
  """
  @spec card(%{name: String.t(), rarity: atom()}) :: map()
  def card(%{name: name, rarity: :gnome}),
    do: %{name: name, rarity: :gnome, stats: Map.new(@stats, &{&1, @joker_stat})}

  def card(%{name: name, rarity: rarity}) do
    bonus = Map.get(@rarity_bonus, rarity, 0)
    stats = Map.new(@stats, &{&1, 1 + :erlang.phash2({name, &1}, 75) + bonus})
    %{name: name, rarity: rarity, stats: stats}
  end

  defp call(id, message) do
    GenServer.call(via(id), message)
  catch
    :exit, _ -> {:error, :not_found}
  end

  defp via(id), do: {:via, Registry, {NeuroScav.BattleRegistry, id}}

  # Server

  @doc false
  def start_link({id, _owner_id, _bot, _opts} = args) do
    GenServer.start_link(__MODULE__, args, name: via(id))
  end

  @impl true
  def init({id, owner_id, bot, %{open: open, size: size}}) do
    state = %{
      id: id,
      players: if(bot, do: [owner_id, @bot], else: [owner_id]),
      bot: bot,
      open: open,
      size: size,
      cards: %{},
      redrawn: MapSet.new(),
      ready: MapSet.new(),
      result: nil,
      wins: %{}
    }

    schedule_bot_turn(state)
    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call({:join, user_id}, _from, %{players: [owner]} = state) when user_id != owner do
    update(%{state | players: [owner, user_id]})
  end

  def handle_call({:join, _user_id}, _from, state), do: reply(state)

  def handle_call({:draw, user_id, locale}, _from, state),
    do: state |> take_draw(user_id, locale) |> respond(state)

  def handle_call({:ready, user_id}, _from, state),
    do: state |> take_ready(user_id) |> respond(state)

  def handle_call({:rematch, user_id}, _from, state) do
    if user_id in state.players and state.result != nil,
      do: rematch(state),
      else: reply_error(state, :not_allowed)
  end

  @impl true
  def handle_info(:bot_turn, state) do
    state = bot_turn(state)
    PubSub.broadcast_battle(state.id, {:battle_updated, state})
    {:noreply, state, @idle_timeout}
  end

  def handle_info(:timeout, state) do
    PubSub.broadcast_battle(state.id, :battle_closed)
    {:stop, :normal, state}
  end

  # turn rules, shared by players and the bot

  defp take_draw(state, user_id, locale) do
    cond do
      user_id not in state.players or state.result != nil ->
        {:error, :not_allowed}

      not Map.has_key?(state.cards, user_id) ->
        {:ok, put_cards(state, user_id, locale)}

      user_id in state.redrawn or user_id in state.ready ->
        {:error, :not_allowed}

      true ->
        {:ok,
         state
         |> put_cards(user_id, locale)
         |> Map.update!(:redrawn, &MapSet.put(&1, user_id))
         |> Map.update!(:ready, &MapSet.put(&1, user_id))
         |> resolve()}
    end
  end

  defp take_ready(state, user_id) do
    if Map.has_key?(state.cards, user_id) and state.result == nil,
      do: {:ok, state |> Map.update!(:ready, &MapSet.put(&1, user_id)) |> resolve()},
      else: {:error, :not_allowed}
  end

  defp rematch(state) do
    state = %{state | cards: %{}, redrawn: MapSet.new(), ready: MapSet.new(), result: nil}
    schedule_bot_turn(state)
    update(state)
  end

  # until the turn comes the bot's seat shows "drawing a card"
  defp schedule_bot_turn(%{bot: %{think_ms: think_ms}}),
    do: Process.send_after(self(), :bot_turn, Enum.random(think_ms))

  defp schedule_bot_turn(_state), do: :ok

  defp bot_turn(%{bot: %{locale: locale}, cards: cards, result: nil} = state)
       when not is_map_key(cards, @bot) do
    {:ok, state} = take_draw(state, @bot, locale)
    total = state.cards[@bot] |> Enum.flat_map(&Map.values(&1.stats)) |> Enum.sum()

    {:ok, state} =
      if total < @average_total * state.size,
        do: take_draw(state, @bot, locale),
        else: take_ready(state, @bot)

    state
  end

  defp bot_turn(state), do: state

  defp put_cards(state, player, locale),
    do: put_in(state.cards[player], for(_ <- 1..state.size, do: draw_card(player, locale)))

  defp draw_card(@bot, locale), do: card(ScavengersServer.generate_uncounted(locale))
  defp draw_card(user_id, locale), do: user_id |> ScavengersServer.generate_card(locale) |> card()

  defp respond({:ok, new_state}, _state), do: update(new_state)
  defp respond({:error, reason}, state), do: reply_error(state, reason)

  defp resolve(%{players: [a, b], result: nil} = state) do
    if MapSet.subset?(MapSet.new([a, b]), state.ready) do
      result = compare(a, state.cards[a], b, state.cards[b])
      %{state | result: result, wins: count_win(state.wins, result.winner)}
    else
      state
    end
  end

  defp resolve(state), do: state

  defp count_win(wins, :draw), do: wins
  defp count_win(wins, winner), do: Map.update(wins, winner, 1, &(&1 + 1))

  # rounds: a %{stat => winner} map per slot
  defp compare(a, cards_a, b, cards_b) do
    rounds =
      Enum.zip_with(cards_a, cards_b, fn card_a, card_b ->
        Map.new(@stats, &{&1, round_winner(a, card_a.stats[&1], b, card_b.stats[&1])})
      end)

    winners = Enum.flat_map(rounds, &Map.values/1)
    score = Map.new([a, b], fn player -> {player, Enum.count(winners, &(&1 == player))} end)

    winner =
      cond do
        score[a] > score[b] -> a
        score[b] > score[a] -> b
        true -> :draw
      end

    %{rounds: rounds, score: score, winner: winner}
  end

  defp round_winner(a, value_a, _b, value_b) when value_a > value_b, do: a
  defp round_winner(_a, value_a, b, value_b) when value_b > value_a, do: b
  defp round_winner(_a, _value_a, _b, _value_b), do: :draw

  defp update(state) do
    PubSub.broadcast_battle(state.id, {:battle_updated, state})
    reply(state)
  end

  defp reply(state), do: {:reply, {:ok, state}, state, @idle_timeout}
  defp reply_error(state, reason), do: {:reply, {:error, reason}, state, @idle_timeout}
end
