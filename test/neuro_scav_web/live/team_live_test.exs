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

    test "locked members survive the next generation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/team_scavengers")
      send(lv.pid, {:team_generated, team(~w(A1 A2 A3 A4 A5))})
      render(lv)

      lv |> element(~s(td[phx-value-index="1"])) |> render_click()
      lv |> element(~s(td[phx-value-index="3"])) |> render_click()
      send(lv.pid, {:team_generated, team(~w(B1 B2 B3))})

      # only the table: names like "A1" can show up in the random session token
      html = lv |> element(".team-table") |> render()
      for name <- ~w(B1 A2 B2 A4 B3), do: assert(html =~ name)
      for name <- ~w(A1 A3 A5), do: refute(html =~ name)
    end

    test "clicking a locked member unlocks it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/team_scavengers")
      send(lv.pid, {:team_generated, team(~w(A1 A2 A3 A4 A5))})
      render(lv)

      assert lv |> element(~s(td[phx-value-index="0"])) |> render_click() =~ "🔒"
      refute lv |> element(~s(td[phx-value-index="0"])) |> render_click() =~ "🔒"
    end

    test "gnome clicked shows gnome team", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/team_scavengers")

      assert render_click(index_live, "gnome_clicked") =~ "ГНОМ ГНОМЫЧ"
    end
  end

  defp team(names), do: Enum.map(names, &%{name: &1, rarity: :common})
end
