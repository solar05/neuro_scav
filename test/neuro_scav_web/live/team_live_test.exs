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

    test "a lock of what isn't a member's index changes nothing, the page lives on",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/team_scavengers")
      send(lv.pid, {:team_generated, team(~w(A1 A2 A3 A4 A5))})
      render(lv)

      for index <- ["x", "1.5", "9", "-1", 3],
          do: render_click(lv, "toggle_lock", %{"index" => index})

      refute render(lv) =~ "🔒"
    end

    test "shows the sets the team collects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/team_scavengers")
      refute has_element?(lv, "#team-sets")

      send(
        lv.pid,
        {:team_generated,
         team(["Гена Лебедев", "Дима Ворона", "Олег Борона", "Анна Кот", "Борис Сом"])}
      )

      assert lv |> element("#team-sets") |> render() =~ "Рифма"
    end

    test "gnome clicked shows gnome team", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/team_scavengers")

      assert render_click(index_live, "gnome_clicked") =~ "ГНОМ ГНОМЫЧ"
    end
  end

  describe "Share" do
    test "shares the whole team once it is generated", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/team_scavengers")
      refute html =~ ~s(data-url="/share/team/)

      send(lv.pid, {:team_generated, team(~w(A1 A2 A3 A4 A5))})

      expected =
        Base.url_encode64(Enum.map_join(~w(A1 A2 A3 A4 A5), "\n", &"#{&1}|common"),
          padding: false
        )

      assert render(lv) =~ ~s(data-url="/share/team/#{expected}")
    end
  end

  defp team(names), do: Enum.map(names, &%{name: &1, rarity: :common})
end
