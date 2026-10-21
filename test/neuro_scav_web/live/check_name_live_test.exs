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

  describe "last name suggestions" do
    test "a single word lists last names instead of checking it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/check_name")

      html = lv |> form("#check-name-form", %{name: "Гена"}) |> render_submit()
      assert html =~ "Фамилии для «Гена»"
      assert html =~ "Что ты такое?"
      assert lv |> element("#name-suggestions .suggest-chip") |> has_element?()
    end

    test "clicking a suggestion checks that name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/check_name")
      lv |> form("#check-name-form", %{name: "Гена"}) |> render_submit()

      chip =
        lv |> element("#name-suggestions .suggest-row:first-of-type .suggest-chip:first-of-type")

      name = chip |> render() |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim()
      chip |> render_click()

      assert lv |> element("#scav-name") |> render() =~ name
      refute lv |> element("#scav-name") |> render() =~ "Что ты такое?"
    end
  end
end
