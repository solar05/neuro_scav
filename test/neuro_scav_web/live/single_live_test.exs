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
end
