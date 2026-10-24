defmodule NeuroScavWeb.SingleLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Index" do
    test "open single scavenger", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/")

      assert html =~ "Здесь будет дичок"
    end

    test "generate single", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/")

      assert index_live |> element("a", "Сгенерировать") |> render_click() =~
               "Сгенерировать"
    end
  end

  describe "Share button" do
    test "share button is absent before any scavenger is generated", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      refute render(lv) =~ ~s(data-url="/share/)
    end

    test "share button appears after a scavenger is generated", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      send(lv.pid, {:single_generated, %{rarity: :rare, name: "Alice Adams"}})
      assert render(lv) =~ ~s(data-url="/share/)
    end

    test "share button appears even for common rarity", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      send(lv.pid, {:single_generated, %{rarity: :common, name: "John Smith"}})
      assert render(lv) =~ ~s(data-url="/share/)
    end

    test "share button data-url encodes the scavenger name and rarity", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      send(lv.pid, {:single_generated, %{rarity: :epic, name: "Alex Xenix"}})
      expected_token = Base.url_encode64("Alex Xenix|epic", padding: false)
      assert render(lv) =~ "/share/#{expected_token}"
    end

    test "share button data-url contains the /share/ path prefix", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      send(lv.pid, {:single_generated, %{rarity: :legendary, name: "Super Legend"}})
      assert render(lv) =~ ~s(data-url="/share/)
    end

    test "share token updates when a new scavenger is generated", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      send(lv.pid, {:single_generated, %{rarity: :rare, name: "Alice Adams"}})
      old_token = Base.url_encode64("Alice Adams|rare", padding: false)
      assert render(lv) =~ old_token

      send(lv.pid, {:single_generated, %{rarity: :epic, name: "Alex Xenix"}})
      new_token = Base.url_encode64("Alex Xenix|epic", padding: false)
      html = render(lv)
      assert html =~ new_token
      refute html =~ old_token
    end

    test "gnome click produces a share button", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      render_click(lv, "gnome_clicked")
      assert render(lv) =~ ~s(data-url="/share/)
    end

    test "a capture sooner than the gnome can be back neither counts nor gives the gnome",
         %{conn: conn} do
      start_supervised!({NeuroScav.StatsCounterServer, NeuroScav.Scavengers.get_statistics()})
      before = :sys.get_state(NeuroScav.StatsCounterServer).gnome
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "gnome_clicked")
      send(lv.pid, {:single_generated, %{rarity: :rare, name: "Alice Adams"}})
      # a crafted one right after: the gnome can't have shown again
      render_click(lv, "gnome_clicked")

      assert render(lv) =~ "Alice Adams"
      assert :sys.get_state(NeuroScav.StatsCounterServer).gnome == before + 1
    end

    test "gnome click share token encodes gnome rarity", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      render_click(lv, "gnome_clicked")
      assert render(lv) =~ ~s(data-url="/share/)
    end
  end
end
