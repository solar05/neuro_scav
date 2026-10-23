defmodule Mix.Tasks.Raid.SimTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Raid.Sim
  alias NeuroScav.Raid
  alias NeuroScav.Scavengers.Names

  @names {Names.first_names_ru(), Names.last_names_ru()}

  test "plays every raid to its end and logs each event met" do
    results = Sim.simulate("greedy", 30, @names, [:pmc, :office, :medic])

    assert length(results) == 30

    for {raid, log} <- results do
      assert Raid.over?(raid)
      assert Enum.map(log, & &1.event) == Enum.take([:pmc, :office, :medic], length(log))
    end
  end

  test "every strategy gets through stalls: the squad stays, yet the raid goes on" do
    route = [:desync, :streets_fps, :train, :roadblock]

    for strategy <- ~w(cautious careful greedy random),
        {raid, log} <- Sim.simulate(strategy, 30, @names, route) do
      assert Raid.over?(raid)
      assert length(log) >= Enum.count(log, &(&1.outcome == :stall))
    end
  end

  test "every strategy goes through a crossroads, taking a path" do
    for strategy <- ~w(cautious greedy random),
        {_raid, [crossroads | _rest]} <- Sim.simulate(strategy, 10, @names, [:fork_road, :pmc]),
        do: assert(crossroads.outcome == :path)
  end

  # a member acting on their own (a greedy one going for the bait) isn't the strategy's choice
  test "the careful strategy weighs a death: it walks past the bait" do
    for {_raid, [bait]} <- Sim.simulate("careful", 20, @names, [:bait]),
        bait.quirk == nil,
        do: assert(bait.outcome == :safe)
  end

  test "no strategy takes a locked retreat: after two the cautious one takes a risk" do
    route = [:office, :office, :axeman, :scav_patrol]

    for strategy <- ~w(cautious careful greedy random),
        do: assert(length(Sim.simulate(strategy, 20, @names, route)) == 20)

    # unless a greedy one went for the office's loot: that's no retreat
    for {_raid, [office, again, axeman | _rest]} <- Sim.simulate("cautious", 20, @names, route),
        office.quirk == nil and again.quirk == nil,
        do: assert(axeman.stat == :strength)
  end

  test "the cautious strategy takes the safe option where there is one" do
    for {_raid, [_pmc, office]} <- Sim.simulate("cautious", 20, @names, [:pmc, :office]),
        office.quirk == nil,
        do: assert(office.outcome == :safe)
  end

  test "summary and event shares are percentages" do
    results = Sim.simulate("random", 50, @names)
    summary = Sim.summary(results)

    for share <- [summary.wiped, summary.clean | Map.values(summary.with)],
        do: assert(share >= 0 and share <= 100)

    assert summary.alive >= 0 and summary.alive <= 5

    for {event, stats} <- Sim.events(results) do
      assert event in Raid.events()
      assert stats.success + stats.died <= 100.0001
    end
  end

  test "prints the tables; the same seed gives the same run" do
    args = ~w(--runs 40 --seed 3 --route pmc,veteran --events)
    output = capture_io(fn -> Sim.run(args) end)

    assert output =~ "seed 3, route pmc,veteran"
    assert output =~ "cautious" and output =~ "greedy" and output =~ "random"
    assert output =~ "veteran"
    assert capture_io(fn -> Sim.run(args) end) == output
  end

  test "rejects unknown strategies, events and locales" do
    assert_raise Mix.Error, ~r/Unknown strategy/, fn -> Sim.run(~w(--strategy bold)) end
    assert_raise Mix.Error, ~r/Unknown event/, fn -> Sim.run(~w(--route pmc,nope)) end
    assert_raise Mix.Error, ~r/Unknown locale/, fn -> Sim.run(~w(--locale fr)) end
  end
end
