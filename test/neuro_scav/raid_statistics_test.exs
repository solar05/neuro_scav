defmodule NeuroScav.RaidStatisticsTest do
  use NeuroScav.DataCase, async: true

  alias NeuroScav.{PubSub, Scavengers}

  defp report(location, alive),
    do: %{location: location, members: Enum.map(alive, &%{alive: &1})}

  test "a finished raid counts in its location's row, raids adding up" do
    :ok = PubSub.subscribe_statistics()

    Scavengers.record_raid(report(:customs, [true, false, true]))
    Scavengers.record_raid(report(:customs, [false, false]))
    Scavengers.record_raid(report(:labs, [true]))

    assert [
             %{location: "customs", raids: 2, wiped: 1, members: 5, survivors: 2},
             %{location: "labs", raids: 1, wiped: 0, members: 1, survivors: 1}
           ] = Scavengers.list_raid_statistics()

    # the statistics page hears of every raid counted
    assert_receive {:raid_statistics_updated, [%{location: "customs", raids: 1}]}
    assert_receive {:raid_statistics_updated, [%{location: "customs", raids: 2}]}
    assert_receive {:raid_statistics_updated, [%{location: "customs"}, %{location: "labs"}]}
  end

  test "a raid of no location (a fixed route) isn't counted" do
    assert Scavengers.record_raid(report(nil, [true])) == :ok
    assert Scavengers.list_raid_statistics() == []
  end
end
