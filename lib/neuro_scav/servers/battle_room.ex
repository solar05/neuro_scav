defmodule NeuroScav.BattleRoom do
  @moduledoc """
  One card battle between two players. The `mode` sets how they get their cards:

  - `:duel` - a card each, one redraw
  - `:team` - a team of `team_size/0` each, one redraw of the whole team
  - `:draft` - teams picked in turns from open cards on the table

  A room is a process per invite link, registered in `NeuroScav.BattleRegistry`
  under `NeuroScav.BattleSupervisor`. The creator is the first player and the
  first other visitor the second; everyone after that only watches. An `open`
  room (`create(owner, open: true)`) is meant for a random opponent rather than
  an invite; the battle LiveView lists it while its owner waits.

  ## Flow

  In a duel or team battle each player draws their cards, then either fights
  with them or redraws all of them once — redrawn cards are final, so they are
  ready right away. In a draft the room deals `2 × team_size + 2` open cards and
  the players pick one at a time in snake order (A B B A A B), everyone sees
  every card; the last pick starts the battle.

  When both players are ready the cards meet slot by slot and are compared stat
  by stat: every stat of every pair is a round, whoever wins more rounds wins
  the battle. A team gets `set_bonus/0` to every stat for each set it collects
  (`ScavengersServer.team_sets/1`), added to its cards as soon as the team is
  complete.

  A rematch starts once both players ask for it (the bot always agrees). It
  keeps the players and the mode, swaps who picks first in a draft and counts
  the battles each player won in `wins` (draws count for nobody).

  ## Turn timer

  While the battle waits for a player, a clock runs until `deadline` (system
  time in ms): `turn_ms` after the last move. When it runs out, the bot's
  logic moves for everyone who still has to — an absent opponent can't stall
  the room.

  ## Presence and chat

  The battle page joins with `monitor: true`, so the room watches it; a player
  whose every page closed is in `away` until they come back.

  The players can chat: a fixed phrase (`phrases/0`, shown in each viewer's
  language) or a text of up to 200 characters, at most one message a second.
  The last 50 messages stay in `chat`; nothing is stored anywhere else.

  Every change is broadcast to `battle:<id>` as `{:battle_updated, state}`.
  The state holds both players' cards; LiveViews render only the viewer's own
  cards until the result is in, so nothing leaks to the browser before the reveal.

  ## Bot

  A room created with `create_with_bot/3` seats a bot as the second player. It
  "thinks" for 2–5 seconds at the start of every battle (and before every
  draft pick), then takes its turn without seeing the opponent's cards: it
  redraws below-average cards and fights with the rest, in a draft it picks
  the strongest card on the table. Bot and draft cards don't count in the
  statistics and aren't announced.

  The bot also chats now and then, in phrases only: it greets the player,
  wishes luck on a rematch, comments the result and answers the player's
  phrases — each time with a chance of `chat_chance` and after a short pause.

  Rooms live in memory and stop after an hour without activity, broadcasting
  `:battle_closed`.
  """

  use GenServer, restart: :temporary

  alias NeuroScav.{PubSub, ScavengersServer}

  @stats [:strength, :agility, :luck]
  @rarity_bonus %{common: 0, uncommon: 5, rare: 10, epic: 15, legendary: 25}
  @set_bonus 5
  # the gnome is a joker: one above the best legendary stat with all three sets (75 + 25 + 3 × 5)
  @joker_stat 116
  @modes [:duel, :team, :draft]
  @idle_timeout :timer.hours(1)
  @bot "bot"
  @bot_think_ms 2_000..5_000
  @bot_chat_chance 0.5
  # a pause before each bot message, as if it were typing
  @bot_chat_ms 800..2_000
  # the bot's answer to each of the player's phrases
  @bot_replies %{hi: :hi, gl: :gl, gg: :gg, again: :again, lucky: :gg, wow: :lucky}
  # mean card without a rarity bonus: 3 stats × 38 (mean of 1..75)
  @average_total 114
  @team_size 3
  @pool_size 2 * @team_size + 2
  @turn_ms :timer.seconds(30)
  @phrases [:hi, :gl, :gg, :again, :lucky, :wow]
  @max_text 200
  @chat_size 50
  @chat_gap_ms 1_000

  # Client API

  @doc "Battle stats in round order."
  @spec stats() :: [atom()]
  def stats, do: @stats

  @doc "Cards per player in a team battle."
  @spec team_size() :: pos_integer()
  def team_size, do: @team_size

  @doc "Bonus to every stat of a team for each set it collects."
  @spec set_bonus() :: pos_integer()
  def set_bonus, do: @set_bonus

  @doc "Seconds a player has for a move."
  @spec turn_seconds() :: pos_integer()
  def turn_seconds, do: div(@turn_ms, 1_000)

  @doc "Chat phrases, in button order."
  @spec phrases() :: [atom()]
  def phrases, do: @phrases

  @doc "Player id of the bot (user ids are UUIDs, so it never clashes)."
  @spec bot() :: String.t()
  def bot, do: @bot

  @doc """
  Opens a room with `owner_id` as the first player. Returns its id for the invite link.

  `open: true` marks it as waiting for any opponent instead of an invited one,
  `mode:` is `:duel` (default), `:team` or `:draft`, `locale:` the language
  of the draft cards and of the cards drawn for a player whose time ran out,
  `turn_ms:` the time for a move (tests pass a long one and send the timeout).
  """
  @spec create(String.t(), keyword()) :: {:ok, String.t()}
  def create(owner_id, opts \\ []), do: start_room(owner_id, nil, opts)

  @doc """
  Opens a room where `owner_id` plays against the bot; the bot draws in `locale`.

  `mode:` works as in `create/2`; `think_ms:` sets the range the bot's thinking
  time is picked from (tests pass a long one and trigger the turn with a
  `:bot_turn` message), `chat_chance:` (0.0..1.0) and `chat_ms:` how often and
  how fast it chats.
  """
  @spec create_with_bot(String.t(), String.t(), keyword()) :: {:ok, String.t()}
  def create_with_bot(owner_id, locale, opts \\ []) do
    bot = %{
      locale: locale,
      think_ms: Keyword.get(opts, :think_ms, @bot_think_ms),
      chat_chance: Keyword.get(opts, :chat_chance, @bot_chat_chance),
      chat_ms: Keyword.get(opts, :chat_ms, @bot_chat_ms)
    }

    start_room(owner_id, bot, Keyword.put(opts, :locale, locale))
  end

  defp start_room(owner_id, bot, opts) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    settings = %{
      open: Keyword.get(opts, :open, false),
      mode: if(opts[:mode] in @modes, do: opts[:mode], else: :duel),
      locale: Keyword.get(opts, :locale, "ru"),
      turn_ms: Keyword.get(opts, :turn_ms, @turn_ms)
    }

    room = {__MODULE__, {id, owner_id, bot, settings}}
    {:ok, _pid} = DynamicSupervisor.start_child(NeuroScav.BattleSupervisor, room)
    {:ok, id}
  end

  @doc """
  Takes the second player's seat if it is free; otherwise the user just watches.

  `monitor: true` (the battle page) makes the room watch the calling process:
  a player is `away` once all their watched processes are gone.
  """
  @spec join(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, :not_found}
  def join(id, user_id, opts \\ []), do: call(id, {:join, user_id, opts})

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
  Takes card `index` from the draft table when it is the player's turn.
  """
  @spec pick(String.t(), String.t(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def pick(id, user_id, index), do: call(id, {:pick, user_id, index})

  @doc """
  Asks for the next battle between the same players once this one is over;
  it starts when both have asked.
  """
  @spec rematch(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def rematch(id, user_id), do: call(id, {:rematch, user_id})

  @doc """
  Sends a chat message from a player: `{:phrase, phrase}` or `{:text, text}`.
  """
  @spec say(String.t(), String.t(), {:phrase, atom()} | {:text, String.t()}) ::
          {:ok, map()} | {:error, atom()}
  def say(id, user_id, message), do: call(id, {:say, user_id, message})

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

  @doc """
  Whose pick it is in a draft: snake order, the `first` player picks first.
  Nil outside a draft, until both players are seated and once the picks are done.
  """
  @spec turn(map()) :: String.t() | nil
  def turn(%{draft: %{first: first}, players: [_, _] = players, result: nil} = state) do
    [a, b] = if first == 0, do: players, else: Enum.reverse(players)
    order = Enum.flat_map(1..state.size, &if(rem(&1, 2) == 1, do: [a, b], else: [b, a]))
    picked = state.cards |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
    Enum.at(order, picked)
  end

  def turn(_state), do: nil

  @doc """
  Compares the cards of players `a` and `b` slot by slot: every stat of every
  pair is a round, `rounds` holds a `%{stat => winner}` map per slot.
  """
  @spec compare(term(), [map()], term(), [map()]) :: map()
  def compare(a, cards_a, b, cards_b) do
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
  def init({id, owner_id, bot, %{open: open, mode: mode, locale: locale, turn_ms: turn_ms}}) do
    state =
      %{
        id: id,
        players: if(bot, do: [owner_id, @bot], else: [owner_id]),
        bot: bot,
        open: open,
        mode: mode,
        size: if(mode == :duel, do: 1, else: @team_size),
        cards: %{},
        sets: %{},
        redrawn: MapSet.new(),
        ready: MapSet.new(),
        rematch: MapSet.new(),
        result: nil,
        wins: %{},
        draft: if(mode == :draft, do: %{first: 0, pool: []}),
        locale: locale,
        turn_ms: turn_ms,
        deadline: nil,
        online: %{},
        away: MapSet.new(),
        chat: [],
        said: %{}
      }
      |> deal()
      |> arm_timer()

    schedule_bot_turn(state)
    bot_say(state, :hi)
    {:ok, state, @idle_timeout}
  end

  @impl true
  def handle_call({:join, user_id, opts}, {pid, _tag}, state) do
    watched = if opts[:monitor], do: watch(state, pid, user_id), else: state

    case watched.players do
      [owner] when user_id != owner -> update(arm_timer(%{watched | players: [owner, user_id]}))
      _players when watched.away != state.away -> update(watched)
      _players -> reply(watched)
    end
  end

  def handle_call({:draw, user_id, locale}, _from, state),
    do: state |> take_draw(user_id, locale) |> respond(state)

  def handle_call({:ready, user_id}, _from, state),
    do: state |> take_ready(user_id) |> respond(state)

  def handle_call({:pick, user_id, index}, _from, state) do
    case take_pick(state, user_id, index) do
      {:ok, new_state} ->
        schedule_bot_turn(new_state)
        update(arm_timer(new_state))

      {:error, reason} ->
        reply_error(state, reason)
    end
  end

  def handle_call({:rematch, user_id}, _from, state) do
    if user_id in state.players and state.result != nil,
      do: state |> Map.update!(:rematch, &MapSet.put(&1, user_id)) |> rematch(),
      else: reply_error(state, :not_allowed)
  end

  def handle_call({:say, user_id, message}, _from, state) do
    now = System.monotonic_time(:millisecond)
    last = Map.get(state.said, user_id, now - @chat_gap_ms)

    with true <- user_id in state.players and user_id != @bot and now - last >= @chat_gap_ms,
         {:ok, entry} <- chat_entry(message) do
      if entry.phrase, do: bot_say(state, @bot_replies[entry.phrase])

      state
      |> add_chat(%{entry | from: user_id})
      |> Map.update!(:said, &Map.put(&1, user_id, now))
      |> update()
    else
      _invalid -> reply_error(state, :not_allowed)
    end
  end

  @impl true
  def handle_info(:bot_turn, state) do
    moved = bot_turn(state)
    # a stray turn message is no move, so it doesn't restart the clock
    moved = if moved == state, do: state, else: arm_timer(moved)
    # a draft may give the bot two picks in a row
    if moved.mode == :draft, do: schedule_bot_turn(moved)
    broadcast(moved)
  end

  # the clock ran out: the bot's logic moves for everyone who still has to
  def handle_info({:turn_timeout, deadline}, %{deadline: deadline} = state) do
    state
    |> waiting()
    |> Enum.reduce(state, &auto_turn(&2, &1, state.locale))
    |> arm_timer()
    |> broadcast()
  end

  def handle_info({:turn_timeout, _stale}, state), do: {:noreply, state, @idle_timeout}

  def handle_info({:bot_say, phrase}, state),
    do: state |> add_chat(%{entry(phrase, nil) | from: @bot}) |> broadcast()

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {user_id, online} = Map.pop(state.online, pid)
    state = %{state | online: online}

    if user_id in state.players and user_id not in Map.values(online),
      do: state |> Map.update!(:away, &MapSet.put(&1, user_id)) |> broadcast(),
      else: {:noreply, state, @idle_timeout}
  end

  def handle_info(:timeout, state) do
    PubSub.broadcast_battle(state.id, :battle_closed)
    {:stop, :normal, state}
  end

  # turn rules, shared by players and the bot

  defp take_draw(state, user_id, locale) do
    cond do
      user_id not in state.players or state.result != nil or state.mode == :draft ->
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
    if Map.has_key?(state.cards, user_id) and state.result == nil and state.mode != :draft,
      do: {:ok, state |> Map.update!(:ready, &MapSet.put(&1, user_id)) |> resolve()},
      else: {:error, :not_allowed}
  end

  defp take_pick(state, user_id, index) do
    pool = if state.draft, do: state.draft.pool, else: []

    if user_id == turn(state) and index in 0..(length(pool) - 1)//1 do
      {card, pool} = List.pop_at(pool, index)
      state = put_in(state.draft.pool, pool)
      state = put_in(state.cards[user_id], Map.get(state.cards, user_id, []) ++ [card])
      {:ok, if(turn(state), do: state, else: finish_draft(state))}
    else
      {:error, :not_allowed}
    end
  end

  defp finish_draft(%{players: players} = state) do
    players
    |> Enum.reduce(state, &put_team(&2, &1, &2.cards[&1]))
    |> Map.put(:ready, MapSet.new(players))
    |> resolve()
  end

  # the bot always agrees
  defp rematch(state) do
    if Enum.all?(state.players, &(&1 == @bot or &1 in state.rematch)) do
      state =
        %{
          state
          | cards: %{},
            sets: %{},
            redrawn: MapSet.new(),
            ready: MapSet.new(),
            rematch: MapSet.new(),
            result: nil
        }
        |> next_draft()
        |> deal()

      state = arm_timer(state)
      schedule_bot_turn(state)
      bot_say(state, :gl)
      update(state)
    else
      update(state)
    end
  end

  # the other player picks first in the next draft
  defp next_draft(%{draft: nil} = state), do: state
  defp next_draft(state), do: update_in(state.draft.first, &(1 - &1))

  defp deal(%{draft: %{}, locale: locale} = state) do
    pool = for _ <- 1..@pool_size, do: card(ScavengersServer.generate_uncounted(locale))
    put_in(state.draft.pool, pool)
  end

  defp deal(state), do: state

  # until the turn comes the bot's seat shows "drawing a card"
  defp schedule_bot_turn(%{bot: %{think_ms: think_ms}} = state) do
    if state.mode != :draft or turn(state) == @bot,
      do: Process.send_after(self(), :bot_turn, Enum.random(think_ms))

    :ok
  end

  defp schedule_bot_turn(_state), do: :ok

  defp bot_turn(%{bot: %{locale: locale}} = state), do: auto_turn(state, @bot, locale)
  defp bot_turn(state), do: state

  # The bot's moves, also made for a player whose time ran out: in a draft it
  # takes the strongest card on the table, otherwise it draws, then redraws
  # below-average cards and fights with the rest.
  defp auto_turn(%{mode: :draft} = state, player, _locale) do
    if turn(state) == player do
      {_card, index} = state.draft.pool |> Enum.with_index() |> Enum.max_by(&total([elem(&1, 0)]))
      {:ok, state} = take_pick(state, player, index)
      state
    else
      state
    end
  end

  defp auto_turn(state, player, locale) do
    cards = state.cards[player]

    cond do
      state.result != nil or player in state.ready ->
        state

      cards == nil ->
        {:ok, state} = take_draw(state, player, locale)
        auto_turn(state, player, locale)

      player not in state.redrawn and total(cards) < @average_total * state.size ->
        {:ok, state} = take_draw(state, player, locale)
        state

      true ->
        {:ok, state} = take_ready(state, player)
        state
    end
  end

  # players the battle waits for; the bot moves on its own
  defp waiting(%{players: [_, _], result: nil} = state) do
    movers =
      if state.mode == :draft,
        do: List.wrap(turn(state)),
        else: Enum.reject(state.players, &(&1 in state.ready))

    List.delete(movers, @bot)
  end

  defp waiting(_state), do: []

  defp arm_timer(state) do
    if waiting(state) == [] do
      %{state | deadline: nil}
    else
      deadline = System.system_time(:millisecond) + state.turn_ms
      Process.send_after(self(), {:turn_timeout, deadline}, state.turn_ms)
      %{state | deadline: deadline}
    end
  end

  defp watch(state, pid, user_id) do
    if not Map.has_key?(state.online, pid), do: Process.monitor(pid)

    %{
      state
      | online: Map.put(state.online, pid, user_id),
        away: MapSet.delete(state.away, user_id)
    }
  end

  defp add_chat(state, entry), do: %{state | chat: Enum.take(state.chat ++ [entry], -@chat_size)}

  # now and then, after a pause as if typing; only rooms with a bot
  defp bot_say(%{bot: %{chat_chance: chance, chat_ms: chat_ms}}, phrase) do
    if :rand.uniform() < chance,
      do: Process.send_after(self(), {:bot_say, phrase}, Enum.random(chat_ms))

    :ok
  end

  defp bot_say(_state, _phrase), do: :ok

  defp bot_comment(@bot), do: Enum.random([:gg, :again])
  defp bot_comment(:draw), do: :wow
  defp bot_comment(_winner), do: Enum.random([:lucky, :gg])

  defp chat_entry({:phrase, phrase}) when phrase in @phrases, do: {:ok, entry(phrase, nil)}

  defp chat_entry({:text, text}) when is_binary(text) do
    case text |> String.trim() |> String.slice(0, @max_text) do
      "" -> :error
      text -> {:ok, entry(nil, text)}
    end
  end

  defp chat_entry(_message), do: :error

  defp entry(phrase, text) do
    %{
      id: System.unique_integer([:positive, :monotonic]),
      from: nil,
      phrase: phrase,
      text: text,
      at: System.system_time(:millisecond)
    }
  end

  defp total(cards), do: cards |> Enum.flat_map(&Map.values(&1.stats)) |> Enum.sum()

  defp put_cards(state, player, locale),
    do: put_team(state, player, for(_ <- 1..state.size, do: draw_card(player, locale)))

  # a team takes its set bonus right away, so its cards show the stats they fight with
  defp put_team(state, player, cards) do
    sets = cards |> Enum.map(& &1.name) |> ScavengersServer.team_sets()
    bonus = @set_bonus * length(sets)
    cards = Enum.map(cards, fn card -> %{card | stats: Map.new(card.stats, &add(&1, bonus))} end)
    %{state | cards: Map.put(state.cards, player, cards), sets: Map.put(state.sets, player, sets)}
  end

  defp add({stat, value}, bonus), do: {stat, value + bonus}

  defp draw_card(@bot, locale), do: card(ScavengersServer.generate_uncounted(locale))
  defp draw_card(user_id, locale), do: user_id |> ScavengersServer.generate_card(locale) |> card()

  defp respond({:ok, new_state}, _state), do: update(arm_timer(new_state))
  defp respond({:error, reason}, state), do: reply_error(state, reason)

  defp resolve(%{players: [a, b], result: nil} = state) do
    if MapSet.subset?(MapSet.new([a, b]), state.ready) do
      result = compare(a, state.cards[a], b, state.cards[b])
      bot_say(state, bot_comment(result.winner))
      %{state | result: result, wins: count_win(state.wins, result.winner)}
    else
      state
    end
  end

  defp resolve(state), do: state

  defp count_win(wins, :draw), do: wins
  defp count_win(wins, winner), do: Map.update(wins, winner, 1, &(&1 + 1))

  defp round_winner(a, value_a, _b, value_b) when value_a > value_b, do: a
  defp round_winner(_a, value_a, b, value_b) when value_b > value_a, do: b
  defp round_winner(_a, _value_a, _b, _value_b), do: :draw

  defp update(state) do
    PubSub.broadcast_battle(state.id, {:battle_updated, state})
    reply(state)
  end

  defp broadcast(state) do
    PubSub.broadcast_battle(state.id, {:battle_updated, state})
    {:noreply, state, @idle_timeout}
  end

  defp reply(state), do: {:reply, {:ok, state}, state, @idle_timeout}
  defp reply_error(state, reason), do: {:reply, {:error, reason}, state, @idle_timeout}
end
