defmodule NeuroScavWeb.CheckNameLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  test "opens the check page", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/check_name")

    assert html =~ "Что ты такое?"
    refute html =~ ~s(data-url="/share/)
  end

  test "shows the rarity of a typed name", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/check_name")

    html = lv |> form("#check-name-form", %{name: "  Алиса   Аврора "}) |> render_submit()
    assert html =~ "Алиса Аврора"
    assert html =~ "Редкий дичок!"
    assert html =~ ~s(data-url="/share/)
  end

  test "finds legendary names regardless of case", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/check_name")

    html = lv |> form("#check-name-form", %{name: "дед мороз"}) |> render_submit()
    assert html =~ "Дед Мороз"
    assert html =~ "Легендарная находка!"
  end

  test "ignores a single word", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/check_name")

    assert lv |> form("#check-name-form", %{name: "Вася"}) |> render_submit() =~
             "Что ты такое?"
  end
end
