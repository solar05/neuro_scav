defmodule NeuroScavWeb.GlossaryLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  test "shows rarity chances", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/glossary")

    assert html =~ ~r/Шанс: \d+\.\d+%/
    assert html =~ "Шанс: 0.05%"
  end

  test "explains the team sets and their bonus", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/glossary")

    assert html =~ "+5 ко всем статам"
    sets = lv |> element("#glossary-sets") |> render()
    for name <- ["Одна буква", "Рифма", "Ровный строй"], do: assert(sets =~ name)
  end
end
