defmodule NeuroScavWeb.WheelLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NeuroScavWeb.NeuroScavengerLive.Wheel

  defp fill(lv, text), do: lv |> element("#wheel-form") |> render_change(%{entries: text})

  defp segment_count(html), do: length(String.split(html, "<path")) - 1

  defp winner(lv),
    do:
      lv
      |> element("#wheel-winner-name")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()
      |> String.trim()

  defp rotation(html), do: Regex.run(~r/rotate\(([\d.]+)deg\)/, html) |> List.last()

  test "target_rotation stops the top pointer inside the chosen segment" do
    for count <- 1..100, _ <- 1..20 do
      index = Enum.random(0..(count - 1))
      current = :rand.uniform() * 10_000
      turns = Enum.random(5..16)
      rotation = Wheel.target_rotation(current, index, count, 0.1 + :rand.uniform() * 0.8, turns)

      under_pointer = :math.fmod(360 - :math.fmod(rotation, 360), 360)
      assert trunc(under_pointer * count / 360) == index
      assert rotation >= current + turns * 360
    end
  end

  test "spin length grows with entries: 6s for 2, 20s for 9, capped" do
    assert Wheel.spin_ms(1) == 6_000
    assert Wheel.spin_ms(2) == 6_000
    assert Wheel.spin_ms(5) == 12_000
    assert Wheel.spin_ms(9) == 20_000
    assert Wheel.spin_ms(100) == 20_000
  end

  test "spin uses the count-based duration for the animation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/wheel")
    fill(lv, Enum.map_join(1..9, "\n", &"n#{&1}"))

    assert lv |> element("#btn-wheel") |> render_click() =~ "transition-duration: 20000ms"
  end

  test "starts with three default entries", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/wheel")

    assert html =~ "Кому повезёт?"
    assert segment_count(html) == 3
    assert html =~ "3/100"
    refute html =~ "Перемешать"
  end

  test "entries become segments, blank lines dropped, limits applied", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/wheel")

    assert lv |> fill("Alice\n\n  Bob  \nCarol\nDave\n") |> segment_count() == 4

    html = fill(lv, Enum.map_join(1..150, "\n", &"n#{&1}"))
    assert segment_count(html) == 100
    refute html =~ "n101"

    html = fill(lv, String.duplicate("x", 50))
    assert html =~ String.duplicate("x", 40)
    refute html =~ String.duplicate("x", 41)
  end

  test "clicking the wheel spins it and locks input until reveal", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/wheel")
    fill(lv, "Alice\nBob\nCarol")

    html = lv |> element("#btn-wheel") |> render_click()
    spun_to = rotation(html)
    assert spun_to != "0"
    assert has_element?(lv, "#btn-wheel[disabled]")
    assert has_element?(lv, "#wheel-entries[disabled]")
    refute has_element?(lv, "#wheel-winner")

    # spin and edits while spinning are ignored
    assert render_click(lv, "spin", %{}) |> rotation() == spun_to
    assert render_change(lv, "update_entries", %{"entries" => "Zed"}) |> segment_count() == 3

    send(lv.pid, :reveal)
    assert winner(lv) in ["Alice", "Bob", "Carol"]
    refute has_element?(lv, "#btn-wheel[disabled]")
  end

  test "remove in the winner modal deletes the entry from the wheel", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/wheel")
    fill(lv, "Alice\nBob\nCarol")
    lv |> element("#btn-wheel") |> render_click()
    send(lv.pid, :reveal)
    winner = winner(lv)

    html = lv |> element("#btn-remove-winner") |> render_click()

    refute has_element?(lv, "#wheel-winner")
    assert segment_count(html) == 2
    refute lv |> element("#wheel-entries") |> render() =~ winner
  end

  test "keep closes the winner modal and leaves entries intact", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/wheel")
    lv |> element("#btn-wheel") |> render_click()
    send(lv.pid, :reveal)
    assert has_element?(lv, "#wheel-winner")

    html = lv |> element("#btn-keep-winner") |> render_click()

    refute has_element?(lv, "#wheel-winner")
    assert segment_count(html) == 3
  end

  test "spin with no entries does nothing", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/wheel")
    fill(lv, "")

    assert has_element?(lv, "#btn-wheel[disabled]")
    assert render_click(lv, "spin", %{}) |> rotation() == "0"
  end
end
