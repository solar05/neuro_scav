defmodule NeuroScavWeb.SingleLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Index" do
    test "open single scavenger", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/single_scavenger")

      assert html =~ "Здесь будет дичок"
    end

    test "generate single", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/single_scavenger")

      assert index_live |> element("a", "Сгенерировать") |> render_click() =~
               "Сгенерировать"
    end
  end

  describe "Streak counter" do
    test "streak badge is hidden initially", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/single_scavenger")

      refute render(lv) =~ "streak-badge"
    end

    test "streak badge is hidden after a single non-common result", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/single_scavenger")

      send(lv.pid, {:single_generated, %{rarity: :rare, name: "Alice Adams"}})

      refute render(lv) =~ "streak-badge"
    end

    test "streak badge appears after two consecutive non-common results", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/single_scavenger")

      send(lv.pid, {:single_generated, %{rarity: :rare, name: "Alice Adams"}})
      send(lv.pid, {:single_generated, %{rarity: :epic, name: "Alex Xenix"}})

      html = render(lv)
      assert html =~ "streak-badge"
      assert html =~ "x2"
    end

    test "streak increments across all non-common rarities", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/single_scavenger")

      for rarity <- [:uncommon, :rare, :epic, :legendary] do
        send(lv.pid, {:single_generated, %{rarity: rarity, name: "Test Name"}})
      end

      assert render(lv) =~ "x4"
    end

    test "streak resets to zero on common result", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/single_scavenger")

      send(lv.pid, {:single_generated, %{rarity: :rare, name: "Alice Adams"}})
      send(lv.pid, {:single_generated, %{rarity: :epic, name: "Alex Xenix"}})
      send(lv.pid, {:single_generated, %{rarity: :common, name: "John Smith"}})

      refute render(lv) =~ "streak-badge"
    end

    test "streak resumes after reset", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/single_scavenger")

      send(lv.pid, {:single_generated, %{rarity: :rare, name: "Alice Adams"}})
      send(lv.pid, {:single_generated, %{rarity: :rare, name: "Bob Brown"}})
      send(lv.pid, {:single_generated, %{rarity: :common, name: "John Smith"}})
      send(lv.pid, {:single_generated, %{rarity: :legendary, name: "Mega Ultra"}})
      send(lv.pid, {:single_generated, %{rarity: :epic, name: "Alex Xenix"}})

      assert render(lv) =~ "x2"
    end

    test "streak badge uses hot class at 5+ streak", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/single_scavenger")

      for _ <- 1..5 do
        send(lv.pid, {:single_generated, %{rarity: :rare, name: "Alice Adams"}})
      end

      assert render(lv) =~ "streak-hot"
    end

    test "streak badge uses legendary class at 10+ streak", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/single_scavenger")

      for _ <- 1..10 do
        send(lv.pid, {:single_generated, %{rarity: :epic, name: "Alex Xenix"}})
      end

      assert render(lv) =~ "streak-legendary"
    end
  end
end
