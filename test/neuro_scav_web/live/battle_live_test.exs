defmodule NeuroScavWeb.BattleLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NeuroScav.BattleRoom

  setup do
    start_supervised!({NeuroScav.ScavengersServer, %{module_name: NeuroScav.Scavengers.Names}})
    :ok
  end

  defp conn_for(user_id),
    do: Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{"user_id" => user_id})

  defp card_name(view, index) do
    view
    |> element("#battle-card-#{index}-0")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
  end

  test "the lobby creates a room and sends the creator into it" do
    {:ok, lv, html} = live(conn_for("a"), ~p"/battle")
    assert html =~ "Создать комнату"

    assert {:error, {:live_redirect, %{to: "/battle/" <> id}}} =
             lv |> element("#btn-battle-create") |> render_click()

    assert {:ok, %{players: ["a"]}} = BattleRoom.join(id, "a")
  end

  defp stop_room_on_exit(id) do
    [{pid, _}] = Registry.lookup(NeuroScav.BattleRegistry, id)
    on_exit(fn -> DynamicSupervisor.terminate_child(NeuroScav.BattleSupervisor, pid) end)
    pid
  end

  test "the lobby starts a battle against the bot" do
    {:ok, lv, _html} = live(conn_for("a"), ~p"/battle")

    assert {:error, {:live_redirect, %{to: "/battle/" <> id}}} =
             lv |> element("#btn-battle-bot") |> render_click()

    stop_room_on_exit(id)
    assert {:ok, %{players: ["a", "bot"]}} = BattleRoom.join(id, "a")
  end

  test "the bot thinks while the player draws, then they fight" do
    {:ok, id} = BattleRoom.create_with_bot("a", "ru", think_ms: 60_000..60_000)
    pid = stop_room_on_exit(id)

    {:ok, lv, html} = live(conn_for("a"), ~p"/battle/#{id}")
    assert html =~ "Бот"
    assert html =~ "Тянет карту…"
    refute html =~ "Скопировать приглашение"

    lv |> element("#btn-battle-draw") |> render_click()
    lv |> element("#btn-battle-ready") |> render_click()
    assert has_element?(lv, ".battle-result.battle-hidden")

    send(pid, :bot_turn)
    _ = :sys.get_state(pid)
    html = render(lv)

    assert html =~ "Победа!" or html =~ "Поражение" or html =~ "Ничья"
    assert has_element?(lv, "#btn-battle-rematch")
  end

  defp find_opponent(user_id) do
    {:ok, lobby, _html} = live(conn_for(user_id), ~p"/battle")

    assert {:error, {:live_redirect, %{to: "/battle/" <> id}}} =
             lobby |> element("#btn-battle-find") |> render_click()

    id
  end

  test "find opponent seats two searchers in one room" do
    id = find_opponent("a")
    stop_room_on_exit(id)

    {:ok, room_a, html} = live(conn_for("a"), ~p"/battle/#{id}")
    assert html =~ "Ищем соперника"

    assert find_opponent("b") == id
    assert render(room_a) =~ "перетянуть можно один раз"

    # a full room leaves the queue, so the next searcher waits in a new one
    other = find_opponent("c")
    stop_room_on_exit(other)
    assert other != id
  end

  test "a room is offered only while its owner waits on the page" do
    id = find_opponent("a")
    stop_room_on_exit(id)

    other = find_opponent("b")
    stop_room_on_exit(other)
    assert other != id
  end

  test "the lobby switches to a team battle or a draft" do
    {:ok, lv, html} = live(conn_for("a"), ~p"/battle")
    refute html =~ "дички бьются парами"

    assert lv |> element("#btn-battle-mode-team") |> render_click() =~ "дички бьются парами"
    assert lv |> element("#btn-battle-mode-draft") |> render_click() =~ "8 открытых карт"

    assert {:error, {:live_redirect, %{to: "/battle/" <> id}}} =
             lv |> element("#btn-battle-bot") |> render_click()

    stop_room_on_exit(id)
    assert {:ok, %{mode: :draft, size: 3}} = BattleRoom.join(id, "a")
  end

  test "a team battle shows three cards a side after the reveal" do
    {:ok, id} = BattleRoom.create("a", mode: :team)
    stop_room_on_exit(id)

    {:ok, a, _html} = live(conn_for("a"), ~p"/battle/#{id}")
    {:ok, b, _html} = live(conn_for("b"), ~p"/battle/#{id}")
    # unknown cards are placeholders, so the arena has all six slots from the start
    assert card_slots(a) == 6

    assert a |> element("#btn-battle-draw") |> render_click() =~ "Перетянуть"
    assert has_element?(a, "#battle-card-0-2")
    refute has_element?(b, "#battle-card-1-0")
    assert card_slots(b) == 6

    a |> element("#btn-battle-ready") |> render_click()
    b |> element("#btn-battle-draw") |> render_click()
    b |> element("#btn-battle-ready") |> render_click()
    assert card_slots(a) == 6

    for view <- [a, b], seat <- [0, 1], do: assert(has_element?(view, "#battle-card-#{seat}-2"))

    # the reveal: 9 rounds of 400ms, each seat's score steps up in the rounds it won
    html = render(a)
    assert html =~ "--rounds: 9; --step: 400ms"

    seats = html |> LazyHTML.from_fragment() |> LazyHTML.query(".battle-seat")
    assert Enum.count(seats) == 2

    for seat <- seats do
      steps = seat |> LazyHTML.query(".battle-score > span") |> Enum.map(&score_step/1)
      won_in = seat |> LazyHTML.query(".battle-stat-win") |> Enum.map(&round_of/1) |> Enum.sort()

      assert steps == [{0, 0} | Enum.with_index(won_in, fn round, won -> {won + 1, round} end)]
    end
  end

  defp card_slots(view),
    do:
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".battle-card")
      |> Enum.count()

  defp score_step(span),
    do: {span |> LazyHTML.text() |> String.trim() |> String.to_integer(), round_of(span)}

  defp round_of(node) do
    [style] = LazyHTML.attribute(node, "style")
    [round] = Regex.run(~r/--round: (\d+)/, style, capture: :all_but_first)
    String.to_integer(round)
  end

  test "find opponent pairs only searchers of the same mode" do
    {:ok, lobby, _html} = live(conn_for("a"), ~p"/battle")
    lobby |> element("#btn-battle-mode-team") |> render_click()

    assert {:error, {:live_redirect, %{to: "/battle/" <> team_id}}} =
             lobby |> element("#btn-battle-find") |> render_click()

    stop_room_on_exit(team_id)
    {:ok, _room, _html} = live(conn_for("a"), ~p"/battle/#{team_id}")

    duel_id = find_opponent("b")
    stop_room_on_exit(duel_id)
    assert duel_id != team_id
  end

  test "an unknown room offers to start a new one" do
    {:ok, _lv, html} = live(conn_for("a"), ~p"/battle/nope")
    assert html =~ "Комната не найдена"
  end

  test "two players fight, everyone else watches, cards stay hidden until the reveal" do
    {:ok, id} = BattleRoom.create("a")

    {:ok, a, html} = live(conn_for("a"), ~p"/battle/#{id}")
    assert html =~ "Скопировать приглашение"

    {:ok, b, _html} = live(conn_for("b"), ~p"/battle/#{id}")
    {:ok, c, html} = live(conn_for("c"), ~p"/battle/#{id}")
    assert html =~ "Ты зритель"
    refute has_element?(c, "#btn-battle-draw")

    a |> element("#btn-battle-draw") |> render_click()
    a_card = card_name(a, 0)
    assert render(b) =~ "Тянет карту…"
    refute render(b) =~ a_card
    refute render(c) =~ a_card

    a |> element("#btn-battle-ready") |> render_click()
    assert render(b) =~ "Карта готова"
    # fighting locks the card in: no redraw offered while waiting
    refute has_element?(a, "#btn-battle-draw")

    b |> element("#btn-battle-draw") |> render_click()
    b |> element("#btn-battle-ready") |> render_click()

    for view <- [a, b, c], do: assert(render(view) =~ a_card)

    outcome = fn view -> Enum.find(["Победа!", "Поражение", "Ничья"], &(render(view) =~ &1)) end

    assert {outcome.(a), outcome.(b)} in [
             {"Победа!", "Поражение"},
             {"Поражение", "Победа!"},
             {"Ничья", "Ничья"}
           ]

    # each player sees their own wins first
    [[mine], [theirs]] =
      Regex.scan(~r/\d+/, a |> element("#battle-series") |> render())

    assert b |> element("#battle-series") |> render() =~ "#{theirs} : #{mine}"

    assert has_element?(a, "#btn-battle-rematch")
    refute has_element?(c, "#btn-battle-rematch")
  end

  test "a draft deals open cards that the players take in turns" do
    {:ok, id} = BattleRoom.create("a", mode: :draft, locale: "ru")
    stop_room_on_exit(id)

    {:ok, a, _html} = live(conn_for("a"), ~p"/battle/#{id}")
    {:ok, b, _html} = live(conn_for("b"), ~p"/battle/#{id}")
    {:ok, c, _html} = live(conn_for("c"), ~p"/battle/#{id}")

    assert render(a) =~ "Твой ход"
    assert render(b) =~ "Соперник выбирает карту"
    assert has_element?(b, "#draft-card-0[disabled]")
    refute has_element?(a, "#draft-card-0[disabled]")
    refute has_element?(a, "#btn-battle-draw")

    first = a |> element("#draft-card-0 .battle-card-name") |> render() |> text()
    a |> element("#draft-card-0") |> render_click()

    # picks are open: the opponent and spectators see them right away
    for view <- [a, b, c], do: assert(view |> element(".battle-arena") |> render() =~ first)
    assert render(b) =~ "Твой ход"

    for player <- [b, b, a, a, b], do: player |> element("#draft-card-0") |> render_click()

    refute has_element?(a, "#draft-pool")
    assert render(a) =~ "Победа!" or render(a) =~ "Поражение" or render(a) =~ "Ничья"
  end

  test "a rematch waits until both players agree" do
    {:ok, id} = BattleRoom.create("a")
    stop_room_on_exit(id)

    {:ok, a, _html} = live(conn_for("a"), ~p"/battle/#{id}")
    {:ok, b, _html} = live(conn_for("b"), ~p"/battle/#{id}")

    for view <- [a, b] do
      view |> element("#btn-battle-draw") |> render_click()
      view |> element("#btn-battle-ready") |> render_click()
    end

    a |> element("#btn-battle-rematch") |> render_click()
    assert render(a) =~ "Ждём ответа соперника"
    refute has_element?(a, "#btn-battle-rematch")
    assert render(b) =~ "Хочет реванш!"
    assert b |> element("#btn-battle-rematch") |> render() =~ "Принять реванш"

    b |> element("#btn-battle-rematch") |> render_click()
    assert has_element?(a, "#btn-battle-draw")
    refute render(a) =~ "Ждём ответа соперника"
  end

  defp text(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim()

  test "a bar shows the time left while the battle waits for a move" do
    {:ok, id} = BattleRoom.create("a")
    stop_room_on_exit(id)

    {:ok, a, _html} = live(conn_for("a"), ~p"/battle/#{id}")
    refute has_element?(a, ".battle-timer > span")

    {:ok, b, _html} = live(conn_for("b"), ~p"/battle/#{id}")
    assert render(a) =~ "--left: "
    assert has_element?(a, ".battle-timer > span")

    for view <- [a, b] do
      view |> element("#btn-battle-draw") |> render_click()
      view |> element("#btn-battle-ready") |> render_click()
    end

    refute has_element?(a, ".battle-timer > span")
  end

  test "players chat with texts and phrases, spectators only read" do
    {:ok, id} = BattleRoom.create("a")
    stop_room_on_exit(id)

    {:ok, a, _html} = live(conn_for("a"), ~p"/battle/#{id}")
    {:ok, b, _html} = live(conn_for("b"), ~p"/battle/#{id}")
    {:ok, c, _html} = live(conn_for("c"), ~p"/battle/#{id}")

    a |> form("#battle-chat-form", %{text: "го в бой"}) |> render_submit()
    b |> element("#chat-phrase-gl") |> render_click()

    for view <- [a, b, c] do
      log = view |> element("#battle-chat-log") |> render()
      assert log =~ "го в бой"
      assert log =~ "Удачи!"
    end

    # the message also pops up over its seat
    assert b |> element(".battle-bubble", "го в бой") |> has_element?()

    refute has_element?(c, "#battle-chat-form")
    refute has_element?(c, "#chat-phrase-gl")
    assert has_element?(c, "#battle-chat.battle-chat-readonly")
  end

  test "muting hides the other player's messages from this page only" do
    {:ok, id} = BattleRoom.create("a")
    stop_room_on_exit(id)

    {:ok, a, _html} = live(conn_for("a"), ~p"/battle/#{id}")
    {:ok, b, _html} = live(conn_for("b"), ~p"/battle/#{id}")

    a |> form("#battle-chat-form", %{text: "спам"}) |> render_submit()
    b |> element("#btn-chat-mute") |> render_click()

    refute render(b) =~ "спам"
    assert a |> element("#battle-chat-log") |> render() =~ "спам"

    b |> element("#btn-chat-mute") |> render_click()
    assert b |> element("#battle-chat-log") |> render() =~ "спам"
  end

  test "an opponent who closed the page is shown as gone, then the bot is offered" do
    {:ok, id} = BattleRoom.create("a")
    pid = stop_room_on_exit(id)

    {:ok, a, _html} = live(conn_for("a"), ~p"/battle/#{id}")
    # b's battle page opens and closes again
    fn -> BattleRoom.join(id, "b", monitor: true) end |> Task.async() |> Task.await()
    _ = :sys.get_state(pid)

    assert render(a) =~ "Вышел из боя"

    a |> element("#btn-battle-draw") |> render_click()
    a |> element("#btn-battle-ready") |> render_click()
    send(pid, {:turn_timeout, :sys.get_state(pid).deadline})
    _ = :sys.get_state(pid)

    refute has_element?(a, "#btn-battle-rematch")
    assert has_element?(a, "#btn-battle-lobby")

    assert {:error, {:live_redirect, %{to: "/battle/" <> bot_room}}} =
             a |> element("#btn-battle-bot-again") |> render_click()

    stop_room_on_exit(bot_room)
    assert {:ok, %{players: ["a", "bot"]}} = BattleRoom.join(bot_room, "a")
  end

  test "the bot's messages show in the chat in the viewer's language" do
    {:ok, id} =
      BattleRoom.create_with_bot("a", "ru",
        think_ms: 60_000..60_000,
        chat_chance: 1.0,
        chat_ms: 0..0
      )

    stop_room_on_exit(id)
    NeuroScav.PubSub.subscribe_battle(id)
    {:ok, a, _html} = live(conn_for("a"), ~p"/battle/#{id}")
    assert_receive {:battle_updated, %{chat: [%{from: "bot"}]}}

    log = a |> element("#battle-chat-log") |> render()
    assert log =~ "Бот:"
    assert log =~ "Привет!"
    assert a |> element(".battle-bubble", "Привет!") |> has_element?()
  end
end
