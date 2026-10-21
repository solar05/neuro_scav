defmodule NeuroScavWeb.CollectionLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NeuroScav.Scavengers.Names

  test "every legendary starts hidden", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/collection")

    total = length(Names.legendary_names_ru())
    assert html =~ "0 / #{total}"
    refute has_element?(lv, ".collection-card-found")
    refute html =~ "Олег Пошлый"
  end

  test "names saved in the browser are revealed, unknown ones ignored", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/collection")

    html =
      lv
      |> element("#collection")
      |> render_hook("load_collection", %{"names" => ["Олег Пошлый", "Вася Пупкин", 42]})

    assert html =~ "1 / #{length(Names.legendary_names_ru())}"
    assert lv |> element(".collection-card-found") |> render() =~ "Олег Пошлый"
    refute html =~ "Вася Пупкин"
  end
end
