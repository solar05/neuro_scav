defmodule NeuroScav.BattleRoomTest do
  use ExUnit.Case, async: false

  alias NeuroScav.BattleRoom

  setup do
    start_supervised!({NeuroScav.ScavengersServer, %{module_name: NeuroScav.Scavengers.Names}})
    {:ok, id} = BattleRoom.create("a")
    [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
    on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)
    NeuroScav.PubSub.subscribe_battle(id)
    %{id: id, pid: pid}
  end

  describe "card/1" do
    test "stats come from the name, so the same name always gets the same card" do
      card = BattleRoom.card(%{name: "Алиса Аврора", rarity: :common})

      assert card == BattleRoom.card(%{name: "Алиса Аврора", rarity: :common})
      assert card.stats |> Map.keys() |> Enum.sort() == Enum.sort(BattleRoom.stats())
      assert Enum.all?(Map.values(card.stats), &(&1 in 1..75))
    end

    test "the gnome beats the best legendary with every set in every stat" do
      gnome = BattleRoom.card(%{name: "ГНОМ ГНОМЫЧ", rarity: :gnome})
      best = 75 + 25 + 3 * BattleRoom.set_bonus()

      assert Enum.all?(Map.values(gnome.stats), &(&1 > best))
    end

    test "rarity adds a bonus to every stat" do
      common = BattleRoom.card(%{name: "Алиса Аврора", rarity: :common})
      legendary = BattleRoom.card(%{name: "Алиса Аврора", rarity: :legendary})

      for stat <- BattleRoom.stats(),
          do: assert(legendary.stats[stat] == common.stats[stat] + 25)
    end
  end

  describe "seats" do
    test "the creator plays first, the next visitor second, everyone else watches", %{id: id} do
      assert {:ok, %{players: ["a"]}} = BattleRoom.join(id, "a")
      assert {:ok, %{players: ["a", "b"]}} = BattleRoom.join(id, "b")
      assert_receive {:battle_updated, %{players: ["a", "b"]}}
      assert {:ok, %{players: ["a", "b"]}} = BattleRoom.join(id, "c")
    end

    test "unknown rooms are reported as not found" do
      assert BattleRoom.join("nope", "a") == {:error, :not_found}
      assert BattleRoom.draw("nope", "a", "ru") == {:error, :not_found}
    end
  end

  describe "battle" do
    setup %{id: id} do
      {:ok, _battle} = BattleRoom.join(id, "b")
      :ok
    end

    test "spectators cannot draw", %{id: id} do
      assert BattleRoom.draw(id, "c", "ru") == {:error, :not_allowed}
    end

    test "fighting needs a card", %{id: id} do
      assert BattleRoom.ready(id, "a") == {:error, :not_allowed}
    end

    test "a redraw is allowed once and locks the card in", %{id: id} do
      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, battle} = BattleRoom.draw(id, "a", "ru")

      assert "a" in battle.redrawn
      assert "a" in battle.ready
      assert BattleRoom.draw(id, "a", "ru") == {:error, :not_allowed}
    end

    test "when both are ready, each stat is a round and most rounds win", %{id: id} do
      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, _battle} = BattleRoom.draw(id, "b", "en")
      assert {:ok, %{result: nil}} = BattleRoom.ready(id, "a")
      {:ok, %{result: result, cards: cards}} = BattleRoom.ready(id, "b")

      assert [_card] = cards["a"]
      assert_rules(result, cards)
      assert BattleRoom.draw(id, "a", "ru") == {:error, :not_allowed}
    end

    test "a rematch starts once both players ask, clears the cards and keeps the players", %{
      id: id
    } do
      assert BattleRoom.rematch(id, "a") == {:error, :not_allowed}

      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, _battle} = BattleRoom.draw(id, "b", "ru")
      {:ok, _battle} = BattleRoom.ready(id, "a")
      {:ok, %{result: %{}}} = BattleRoom.ready(id, "b")

      assert BattleRoom.rematch(id, "c") == {:error, :not_allowed}

      assert {:ok, %{result: %{}, rematch: rematch}} = BattleRoom.rematch(id, "b")
      assert MapSet.to_list(rematch) == ["b"]
      # asking twice doesn't count for the other player
      assert {:ok, %{result: %{}}} = BattleRoom.rematch(id, "b")

      assert {:ok, %{players: ["a", "b"], cards: cards, result: nil, rematch: rematch}} =
               BattleRoom.rematch(id, "a")

      assert cards == %{}
      assert MapSet.size(rematch) == 0
    end

    test "a rematch keeps the count of battles won", %{id: id} do
      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, _battle} = BattleRoom.draw(id, "b", "ru")
      {:ok, _battle} = BattleRoom.ready(id, "a")
      {:ok, %{result: %{winner: winner}, wins: wins}} = BattleRoom.ready(id, "b")

      assert wins == if(winner == :draw, do: %{}, else: %{winner => 1})
      {:ok, _battle} = BattleRoom.rematch(id, "a")
      assert {:ok, %{wins: ^wins, result: nil}} = BattleRoom.rematch(id, "b")
    end
  end

  defp start_room(opts) do
    {:ok, id} = BattleRoom.create("a", opts)
    [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
    on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)
    {id, pid}
  end

  test "in a team battle every stat of every pair is a round" do
    {id, _pid} = start_room(mode: :team)

    {:ok, _battle} = BattleRoom.join(id, "b")
    {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
    {:ok, _battle} = BattleRoom.draw(id, "b", "ru")
    {:ok, _battle} = BattleRoom.ready(id, "a")
    {:ok, %{result: result, cards: cards} = battle} = BattleRoom.ready(id, "b")

    assert BattleRoom.team_size() == 3
    assert length(cards["a"]) == 3
    assert length(result.rounds) == 3
    assert_rules(result, cards)
    assert_sets(battle)
  end

  test "a room is a duel unless it asks for a team or a draft" do
    for {opts, size} <- [{[], 1}, {[mode: :bogus], 1}, {[mode: :team], 3}, {[mode: :draft], 3}] do
      {id, _pid} = start_room(opts)
      assert {:ok, %{size: ^size}} = BattleRoom.join(id, "a")
    end
  end

  describe "draft" do
    setup do
      {id, _pid} = start_room(mode: :draft, locale: "en")
      %{draft_id: id}
    end

    test "deals open cards and waits for the second player", %{draft_id: id} do
      assert {:ok, %{draft: %{pool: pool}} = battle} = BattleRoom.join(id, "a")
      assert length(pool) == 2 * BattleRoom.team_size() + 2
      assert BattleRoom.turn(battle) == nil
      assert BattleRoom.pick(id, "a", 0) == {:error, :not_allowed}
    end

    test "players pick in snake order and the last pick starts the battle", %{draft_id: id} do
      {:ok, battle} = BattleRoom.join(id, "b")
      assert BattleRoom.draw(id, "a", "ru") == {:error, :not_allowed}
      assert BattleRoom.pick(id, "b", 0) == {:error, :not_allowed}
      assert BattleRoom.pick(id, "a", 99) == {:error, :not_allowed}

      [first, second, third | _] = battle.draft.pool

      {:ok, battle} = BattleRoom.pick(id, "a", 0)
      assert battle.cards["a"] == [first]
      assert BattleRoom.ready(id, "a") == {:error, :not_allowed}

      {:ok, battle} =
        Enum.reduce(~w(b b a a), {:ok, battle}, fn player, {:ok, battle} ->
          assert BattleRoom.turn(battle) == player
          BattleRoom.pick(id, player, 0)
        end)

      assert battle.cards["b"] |> Enum.take(2) |> Enum.map(& &1.name) ==
               Enum.map([second, third], & &1.name)

      assert BattleRoom.turn(battle) == "b"
      assert battle.result == nil
      {:ok, %{result: result, cards: cards} = battle} = BattleRoom.pick(id, "b", 0)

      assert length(battle.draft.pool) == 2
      assert_rules(result, cards)
      assert_sets(battle)
    end

    test "the other player picks first after a rematch", %{draft_id: id} do
      {:ok, _battle} = BattleRoom.join(id, "b")
      for player <- ~w(a b b a a b), do: {:ok, _battle} = BattleRoom.pick(id, player, 0)

      {:ok, _battle} = BattleRoom.rematch(id, "a")
      {:ok, battle} = BattleRoom.rematch(id, "b")

      assert length(battle.draft.pool) == 2 * BattleRoom.team_size() + 2
      assert BattleRoom.turn(battle) == "b"
    end
  end

  # a team gets the set bonus on every stat of every card
  defp assert_sets(%{cards: cards, sets: sets}) do
    for {player, team} <- cards do
      assert sets[player] == team |> Enum.map(& &1.name) |> NeuroScav.ScavengersServer.team_sets()
      bonus = BattleRoom.set_bonus() * length(sets[player])

      for card <- team,
          stat <- BattleRoom.stats(),
          do: assert(card.stats[stat] == BattleRoom.card(card).stats[stat] + bonus)
    end
  end

  # the rules spelled out: cards meet slot by slot, every stat of a pair is a round
  defp assert_rules(result, %{"a" => cards_a, "b" => cards_b}) do
    expected_rounds =
      Enum.zip_with(cards_a, cards_b, fn a, b ->
        Map.new(BattleRoom.stats(), &{&1, higher(a.stats[&1], b.stats[&1])})
      end)

    assert result.rounds == expected_rounds

    winners = Enum.flat_map(expected_rounds, &Map.values/1)
    score = %{"a" => Enum.count(winners, &(&1 == "a")), "b" => Enum.count(winners, &(&1 == "b"))}
    assert result.score == score

    expected_winner =
      cond do
        score["a"] > score["b"] -> "a"
        score["b"] > score["a"] -> "b"
        true -> :draw
      end

    assert result.winner == expected_winner
  end

  defp higher(a, b) when a > b, do: "a"
  defp higher(a, b) when b > a, do: "b"
  defp higher(_a, _b), do: :draw

  describe "bot" do
    # a long think time keeps the bot waiting until the test sends :bot_turn itself;
    # a quiet bot keeps chat messages out of the states the tests compare
    setup do
      {:ok, id} =
        BattleRoom.create_with_bot("a", "ru", think_ms: 60_000..60_000, chat_chance: 0.0)

      [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
      on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)
      NeuroScav.PubSub.subscribe_battle(id)
      %{bot_room: id, bot_pid: pid}
    end

    # earlier updates (the player's moves) stay in the mailbox: wait for the one with the bot's card
    defp bot_turn(pid) do
      bot = BattleRoom.bot()
      send(pid, :bot_turn)
      assert_receive {:battle_updated, %{cards: %{^bot => _}} = battle}
      battle
    end

    test "takes the second seat and thinks before its turn", %{bot_room: id, bot_pid: pid} do
      bot = BattleRoom.bot()
      assert {:ok, %{players: ["a", ^bot], cards: cards}} = BattleRoom.join(id, "c")
      assert cards == %{}

      battle = bot_turn(pid)
      assert Map.has_key?(battle.cards, bot)
      assert bot in battle.ready
    end

    test "doesn't move instantly by default (it thinks 2 to 5 seconds)" do
      {:ok, id} = BattleRoom.create_with_bot("a", "ru")
      [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
      on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)

      assert {:ok, %{cards: cards}} = BattleRoom.join(id, "a")
      assert cards == %{}
    end

    test "keeps only an above-average card, otherwise redraws", %{bot_pid: pid} do
      bot = BattleRoom.bot()
      battle = bot_turn(pid)
      [card] = battle.cards[bot]
      total = card.stats |> Map.values() |> Enum.sum()

      assert bot in battle.redrawn or total >= 114
    end

    test "a ready player waits for the bot; a rematch makes it think again", %{
      bot_room: id,
      bot_pid: pid
    } do
      bot = BattleRoom.bot()
      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      assert {:ok, %{result: nil}} = BattleRoom.ready(id, "a")
      assert %{result: %{winner: _}} = bot_turn(pid)

      assert {:ok, %{result: nil, cards: cards}} = BattleRoom.rematch(id, "a")
      assert cards == %{}
      assert bot in bot_turn(pid).ready
    end

    test "agrees to a rematch at once", %{bot_room: id, bot_pid: pid} do
      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, _battle} = BattleRoom.ready(id, "a")
      %{result: %{}} = bot_turn(pid)

      assert {:ok, %{result: nil}} = BattleRoom.rematch(id, "a")
    end

    test "picks the strongest card on its draft turns" do
      {:ok, id} = BattleRoom.create_with_bot("a", "ru", mode: :draft, think_ms: 60_000..60_000)
      [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
      on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)
      bot = BattleRoom.bot()

      {:ok, battle} = BattleRoom.pick(id, "a", 0)
      assert BattleRoom.turn(battle) == bot
      best = Enum.max_by(battle.draft.pool, &(&1.stats |> Map.values() |> Enum.sum()))

      send(pid, :bot_turn)
      %{cards: cards} = :sys.get_state(pid)
      assert cards[bot] == [best]
    end

    test "chats: greets, answers phrases, comments the result, wishes luck on a rematch" do
      {:ok, id} =
        BattleRoom.create_with_bot("a", "ru",
          think_ms: 60_000..60_000,
          chat_chance: 1.0,
          chat_ms: 0..0
        )

      [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
      on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)
      NeuroScav.PubSub.subscribe_battle(id)
      bot = BattleRoom.bot()

      assert_receive {:battle_updated, %{chat: [%{from: ^bot, phrase: :hi}]}}

      {:ok, _battle} = BattleRoom.say(id, "a", {:phrase, :gl})
      assert_receive {:battle_updated, %{chat: [_hi, _gl, %{from: ^bot, phrase: :gl}]}}

      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, _battle} = BattleRoom.ready(id, "a")
      send(pid, :bot_turn)

      assert_receive {:battle_updated,
                      %{
                        chat: [_, _, _, %{from: ^bot, phrase: comment}],
                        result: %{winner: winner}
                      }}

      expected =
        case winner do
          ^bot -> [:gg, :again]
          :draw -> [:wow]
          _player -> [:lucky, :gg]
        end

      assert comment in expected

      {:ok, _battle} = BattleRoom.rematch(id, "a")
      assert_receive {:battle_updated, %{chat: [_, _, _, _, %{from: ^bot, phrase: :gl}]}}
    end

    test "a quiet bot never chats", %{bot_room: id} do
      bot = BattleRoom.bot()
      {:ok, _battle} = BattleRoom.say(id, "a", {:phrase, :hi})
      refute_receive {:battle_updated, %{chat: [_hi, %{from: ^bot}]}}, 100
    end

    test "a stray turn message changes nothing", %{bot_room: id, bot_pid: pid} do
      bot_turn(pid)
      {:ok, before} = BattleRoom.join(id, "a")
      assert bot_turn(pid) == before
    end
  end

  describe "turn timer" do
    setup do
      {id, pid} = start_room(turn_ms: 60_000)
      %{timer_id: id, timer_pid: pid}
    end

    test "runs only while the battle waits for a move", %{timer_id: id} do
      assert {:ok, %{deadline: nil}} = BattleRoom.join(id, "a")
      assert {:ok, %{deadline: deadline}} = BattleRoom.join(id, "b")
      assert is_integer(deadline)

      for player <- ~w(a b) do
        {:ok, _battle} = BattleRoom.draw(id, player, "ru")
        {:ok, _battle} = BattleRoom.ready(id, player)
      end

      assert {:ok, %{deadline: nil, result: %{}}} = BattleRoom.join(id, "a")
    end

    test "when the time runs out the moves are made for whoever still has to", %{
      timer_id: id,
      timer_pid: pid
    } do
      {:ok, _battle} = BattleRoom.join(id, "b")
      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, %{deadline: deadline}} = BattleRoom.ready(id, "a")

      send(pid, {:turn_timeout, deadline})
      battle = :sys.get_state(pid)

      assert [_card] = battle.cards["b"]
      assert "b" in battle.ready
      assert battle.result != nil
    end

    test "a timeout of an earlier move changes nothing", %{timer_id: id, timer_pid: pid} do
      {:ok, battle} = BattleRoom.join(id, "b")
      send(pid, {:turn_timeout, battle.deadline - 1})
      assert :sys.get_state(pid) == battle
    end

    test "in a draft the player on turn takes the strongest card" do
      {id, pid} = start_room(mode: :draft, turn_ms: 60_000)
      {:ok, battle} = BattleRoom.join(id, "b")
      best = Enum.max_by(battle.draft.pool, &(&1.stats |> Map.values() |> Enum.sum()))

      send(pid, {:turn_timeout, battle.deadline})
      assert :sys.get_state(pid).cards["a"] == [best]
    end
  end

  describe "presence" do
    # a battle page that opens and closes again
    defp visit(id, user_id) do
      fn -> BattleRoom.join(id, user_id, monitor: true) end |> Task.async() |> Task.await()
    end

    defp await_away(user_id) do
      receive do
        {:battle_updated, %{away: away}} ->
          if user_id in away, do: away, else: await_away(user_id)
      after
        1_000 -> flunk("#{user_id} never went away")
      end
    end

    test "a player whose battle page closed is away until they come back", %{id: id} do
      {:ok, _battle} = BattleRoom.join(id, "b")
      visit(id, "b")
      await_away("b")

      {:ok, %{away: away}} = BattleRoom.join(id, "b", monitor: true)
      refute "b" in away
    end

    test "spectators and players who never opened the page are not away", %{id: id, pid: pid} do
      {:ok, _battle} = BattleRoom.join(id, "b")
      visit(id, "c")
      assert MapSet.size(:sys.get_state(pid).away) == 0
    end
  end

  describe "chat" do
    setup %{id: id} do
      {:ok, _battle} = BattleRoom.join(id, "b")
      :ok
    end

    test "players send phrases and trimmed texts, spectators can't", %{id: id} do
      assert {:ok, %{chat: [%{from: "a", phrase: :gg, text: nil}]}} =
               BattleRoom.say(id, "a", {:phrase, :gg})

      long = String.duplicate("x", 300)
      {:ok, %{chat: [_gg, message]}} = BattleRoom.say(id, "b", {:text, "  #{long} "})
      assert message.text == String.slice(long, 0, 200)

      assert BattleRoom.say(id, "c", {:phrase, :gg}) == {:error, :not_allowed}
    end

    test "rejects empty texts, unknown phrases and a second message within a second", %{id: id} do
      assert BattleRoom.say(id, "a", {:text, "   "}) == {:error, :not_allowed}
      assert BattleRoom.say(id, "a", {:phrase, :nope}) == {:error, :not_allowed}
      assert {:ok, _battle} = BattleRoom.say(id, "a", {:text, "hi"})
      assert BattleRoom.say(id, "a", {:text, "again"}) == {:error, :not_allowed}
    end

    test "keeps the last 50 messages and doesn't touch the clock", %{id: id, pid: pid} do
      %{deadline: deadline} = :sys.get_state(pid)

      for n <- 1..51 do
        # skip the one-second gap between messages
        :sys.replace_state(pid, &%{&1 | said: %{}})
        {:ok, _battle} = BattleRoom.say(id, "a", {:text, "#{n}"})
      end

      %{chat: chat, deadline: ^deadline} = :sys.get_state(pid)
      assert length(chat) == 50
      assert hd(chat).text == "2"
    end
  end

  test "an idle room closes and tells its viewers", %{pid: pid} do
    ref = Process.monitor(pid)
    send(pid, :timeout)

    assert_receive :battle_closed
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end
end
