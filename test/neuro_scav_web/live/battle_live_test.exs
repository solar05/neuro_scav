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
    |> element("#battle-card-#{index}")
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
    refute render(lv) =~ "battle-result"

    send(pid, :bot_turn)
    _ = :sys.get_state(pid)
    html = render(lv)

    assert html =~ "Победа!" or html =~ "Поражение" or html =~ "Ничья"
    assert has_element?(lv, "#btn-battle-rematch")
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

    b |> element("#btn-battle-draw") |> render_click()
    b |> element("#btn-battle-ready") |> render_click()

    for view <- [a, b, c], do: assert(render(view) =~ a_card)

    outcome = fn view -> Enum.find(["Победа!", "Поражение", "Ничья"], &(render(view) =~ &1)) end

    assert {outcome.(a), outcome.(b)} in [
             {"Победа!", "Поражение"},
             {"Поражение", "Победа!"},
             {"Ничья", "Ничья"}
           ]

    assert has_element?(a, "#btn-battle-rematch")
    refute has_element?(c, "#btn-battle-rematch")
  end
end
