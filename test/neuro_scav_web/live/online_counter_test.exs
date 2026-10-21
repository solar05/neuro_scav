defmodule NeuroScavWeb.OnlineCounterTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NeuroScavWeb.Presence

  setup do
    Phoenix.PubSub.subscribe(NeuroScav.PubSub, "online")
    :ok
  end

  defp conn_for(user_id),
    do: Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{"user_id" => user_id})

  defp shown_count(view) do
    [_, count] = Regex.run(~r/Онлайн: (\d+)/, render(view))
    String.to_integer(count)
  end

  # pages recount on presence_diff; once the test has the diff, every page has it queued too
  defp await_diff(user_id, kind) do
    assert_receive %Phoenix.Socket.Broadcast{
      event: "presence_diff",
      payload: %{^kind => %{^user_id => _}}
    }
  end

  test "the badge appears once the page is connected" do
    refute build_conn() |> get(~p"/") |> html_response(200) =~ "Онлайн:"

    {:ok, view, _html} = live(conn_for("online-a"), ~p"/")
    await_diff("online-a", :joins)

    assert Map.has_key?(Presence.list("online"), "online-a")
    assert shown_count(view) == map_size(Presence.list("online"))
  end

  test "counts users, not tabs, and follows them coming and going" do
    {:ok, a, _html} = live(conn_for("online-a"), ~p"/")
    await_diff("online-a", :joins)
    before = shown_count(a)

    {:ok, _second_tab, _html} = live(conn_for("online-a"), ~p"/statistics")
    await_diff("online-a", :joins)
    assert shown_count(a) == before

    {:ok, b, _html} = live(conn_for("online-b"), ~p"/wheel")
    await_diff("online-b", :joins)
    assert shown_count(a) == before + 1

    Presence.untrack(b.pid, "online", "online-b")
    await_diff("online-b", :leaves)
    assert shown_count(a) == before
  end
end
