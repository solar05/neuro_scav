defmodule NeuroScavWeb.StatisticsLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Index" do
    test "open statistics", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/statistics")

      assert html =~ "Легендарные"
    end

    test "tells how raids went, a row per location and the totals, as they finish", %{
      conn: conn
    } do
      {:ok, lv, html} = live(conn, ~p"/statistics")
      assert html =~ "Из вылазок пока никто не возвращался"

      NeuroScav.Scavengers.record_raid(%{
        location: :customs,
        members: [%{alive: true}, %{alive: false}]
      })

      NeuroScav.Scavengers.record_raid(%{location: :labs, members: [%{alive: false}]})

      assert lv |> element("#raid-stats-customs") |> render() =~ ~r/Таможня.*1.*0%.*50%/s
      assert lv |> element("#raid-stats-labs") |> render() =~ ~r/Лаборатория.*1.*100%.*0%/s
      assert lv |> element("#raid-stats-total") |> render() =~ ~r/Всего.*2.*50%.*33%/s
    end
  end
end
