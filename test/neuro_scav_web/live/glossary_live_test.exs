defmodule NeuroScavWeb.GlossaryLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  test "shows rarity chances", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/glossary")

    assert html =~ ~r/Шанс: \d+\.\d+%/
    assert html =~ "Шанс: 0.05%"
  end
end
