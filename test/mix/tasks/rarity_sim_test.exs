defmodule Mix.Tasks.Rarity.SimTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Rarity.Sim

  setup do
    :rand.seed(:exsss, {1, 2, 3})
    :ok
  end

  test "counts every scavenger once, the rarities near their odds" do
    rows = Sim.distribution("ru", 20_000)

    assert Enum.map(rows, & &1.rarity) == [:gnome, :legendary, :epic, :rare, :uncommon, :common]
    assert rows |> Enum.map(& &1.count) |> Enum.sum() == 20_000
    assert_in_delta rows |> Enum.map(& &1.expected) |> Enum.sum(), 100, 1.0e-6
    for %{sigma: sigma} <- rows, do: assert(abs(sigma) < 4)
  end

  test "the gnome takes its odds, or nothing without them" do
    assert [%{rarity: :gnome, count: 500, expected: 100.0} | _] = Sim.distribution("en", 500, 1)
    assert [%{rarity: :gnome, count: 0, sigma: nil} | _] = Sim.distribution("en", 500, nil)
  end

  test "prints a table, or CSV rows the same for the same seed" do
    table = capture_io(fn -> Sim.run(~w(--runs 300 --locale de --seed 7)) end)
    assert table =~ "300 scavengers per locale, seed 7"
    assert table =~ ~r/^legendary\s+\d+/m

    csv = fn -> capture_io(fn -> Sim.run(~w(--runs 300 --locale ja --seed 7 --csv)) end) end
    output = csv.()

    assert [header | lines] = String.split(output, "\n", trim: true)
    assert header == "seed,runs,locale,rarity,count,share,expected,sigma"
    assert length(lines) == 6 and Enum.all?(lines, &String.starts_with?(&1, "7,300,ja,"))
    assert csv.() == output
  end

  test "an unknown locale is an error" do
    assert_raise Mix.Error, ~r/Unknown locale xx/, fn -> Sim.run(~w(--locale xx)) end
  end
end
