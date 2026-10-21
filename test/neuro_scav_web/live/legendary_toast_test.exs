defmodule NeuroScavWeb.LegendaryToastTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: Plug.Test.init_test_session(conn, %{"user_id" => "me"})}
  end

  test "someone else's legendary shows up as a toast on any page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/statistics")

    NeuroScav.PubSub.broadcast_find("someone-else", "Дед Мороз")
    assert_push_event(lv, "legendary-found", %{text: text})
    assert text =~ "Дед Мороз"
  end

  test "the finder's own pages skip it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    NeuroScav.PubSub.broadcast_find("me", "Дед Мороз")
    _ = render(lv)
    refute_push_event(lv, "legendary-found", %{})
  end
end
