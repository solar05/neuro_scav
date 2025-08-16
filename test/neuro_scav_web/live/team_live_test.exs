defmodule NeuroScavWeb.TeamLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Index" do
    test "open team scavenger", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/team_scavengers")

      assert html =~ "Здесь будет дичок"
    end

    test "generate team", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/team_scavengers")

      assert index_live |> element("a", "Сгенерировать команду") |> render_click() =~
               "Сгенерировать команду"
    end
  end
end
