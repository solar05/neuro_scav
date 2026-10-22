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

    test "the gnome beats the best legendary in every stat" do
      gnome = BattleRoom.card(%{name: "ГНОМ ГНОМЫЧ", rarity: :gnome})
      best = 75 + 25

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

    test "a rematch clears the cards and keeps the players", %{id: id} do
      assert BattleRoom.rematch(id, "a") == {:error, :not_allowed}

      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, _battle} = BattleRoom.draw(id, "b", "ru")
      {:ok, _battle} = BattleRoom.ready(id, "a")
      {:ok, %{result: %{}}} = BattleRoom.ready(id, "b")

      assert BattleRoom.rematch(id, "c") == {:error, :not_allowed}

      assert {:ok, %{players: ["a", "b"], cards: cards, result: nil}} =
               BattleRoom.rematch(id, "b")

      assert cards == %{}
    end

    test "a rematch keeps the count of battles won", %{id: id} do
      {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
      {:ok, _battle} = BattleRoom.draw(id, "b", "ru")
      {:ok, _battle} = BattleRoom.ready(id, "a")
      {:ok, %{result: %{winner: winner}, wins: wins}} = BattleRoom.ready(id, "b")

      assert wins == if(winner == :draw, do: %{}, else: %{winner => 1})
      assert {:ok, %{wins: ^wins}} = BattleRoom.rematch(id, "a")
    end
  end

  test "in a team battle every stat of every pair is a round" do
    {:ok, id} = BattleRoom.create("a", size: BattleRoom.team_size())
    [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
    on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)

    {:ok, _battle} = BattleRoom.join(id, "b")
    {:ok, _battle} = BattleRoom.draw(id, "a", "ru")
    {:ok, _battle} = BattleRoom.draw(id, "b", "ru")
    {:ok, _battle} = BattleRoom.ready(id, "a")
    {:ok, %{result: result, cards: cards}} = BattleRoom.ready(id, "b")

    assert length(cards["a"]) == BattleRoom.team_size()
    assert length(result.rounds) == BattleRoom.team_size()
    assert_rules(result, cards)
  end

  test "a room is a duel unless it asks for a full team" do
    for {opts, size} <- [{[], 1}, {[size: 3], 1}, {[size: BattleRoom.team_size()], 5}] do
      {:ok, id} = BattleRoom.create("a", opts)
      [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
      on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)

      assert {:ok, %{size: ^size}} = BattleRoom.join(id, "a")
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
    # a long think time keeps the bot waiting until the test sends :bot_turn itself
    setup do
      {:ok, id} = BattleRoom.create_with_bot("a", "ru", think_ms: 60_000..60_000)
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

    test "a stray turn message changes nothing", %{bot_room: id, bot_pid: pid} do
      bot_turn(pid)
      {:ok, before} = BattleRoom.join(id, "a")
      assert bot_turn(pid) == before
    end
  end

  test "an idle room closes and tells its viewers", %{pid: pid} do
    ref = Process.monitor(pid)
    send(pid, :timeout)

    assert_receive :battle_closed
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end
end
