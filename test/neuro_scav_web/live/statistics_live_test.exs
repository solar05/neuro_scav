defmodule NeuroScavWeb.StatisticsLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Index" do
    test "open statistics", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/statistics")

      assert html =~ "Легендарные"
    end
  end
end
