defmodule NeuroScav.RaidReportTest do
  use ExUnit.Case, async: true

  alias NeuroScav.Raid
  alias NeuroScav.Raid.Report

  @squad [
    %{name: "Алиса Аврора", rarity: :common},
    %{name: "Гена Лена", rarity: :epic},
    %{name: "Дед Мороз", rarity: :legendary}
  ]

  @report %{
    location: :customs,
    exit: :exit_train,
    members: [
      %{name: "Алиса Аврора", rarity: :common, alive: true},
      %{name: "Гена Лена", rarity: :epic, alive: false}
    ],
    loot: [:sj6, :pkm],
    lang: "de"
  }

  defp token(data), do: data |> Jason.encode!() |> Base.url_encode64(padding: false)

  test "a finished raid in short: the exit, who made it, the loot alive finders carried out" do
    raid = Raid.new(@squad, [:exit_car], %{weather: :clear, daytime: :morning})
    # the second member fell, their sj6 stays behind; the first's rooster comes out
    raid = %{raid | stash: [%{item: :rooster, owner: 0}, %{item: :sj6, owner: 1}]}
    raid = put_in(raid.squad, List.update_at(raid.squad, 1, &%{&1 | alive: false}))
    raid = Raid.choose(raid, 1, 1)

    assert Raid.over?(raid)

    assert %{exit: :exit_car, location: nil, loot: [:rooster], lang: "en", members: members} =
             Report.new(raid, "en")

    assert Enum.map(members, & &1.alive) == [true, false, true]
    assert Report.new(raid, "klingon").lang == "ru"
  end

  test "a report goes through a link and comes back the same" do
    assert {:ok, @report} = @report |> Report.encode() |> Report.decode()
    assert {:ok, %{exit: nil}} = %{@report | exit: nil} |> Report.encode() |> Report.decode()
  end

  test "anything but a report's token is no report" do
    good = %{
      "v" => 1,
      "l" => "customs",
      "e" => nil,
      "m" => [["Алиса Аврора", "common", 1]],
      "i" => ["sj6"],
      "g" => "ru"
    }

    assert {:ok, _report} = Report.decode(token(good))

    for bad <- [
          %{good | "v" => 2},
          %{good | "l" => "moon"},
          %{good | "e" => "exit_teleport"},
          %{good | "i" => ["sj6", "nuke"]},
          %{good | "i" => [nil]},
          %{good | "m" => []},
          %{good | "m" => [["", "common", 1]]},
          %{good | "m" => [["Алиса", "mythic", 1]]},
          %{good | "m" => [["Алиса", "common", 2]]},
          %{good | "m" => List.duplicate(["Алиса", "common", 1], 6)},
          %{good | "m" => [[String.duplicate("а", 41), "common", 1]]}
        ],
        do: assert(Report.decode(token(bad)) == :error, inspect(bad))

    assert Report.decode("not a token") == :error
    assert Report.decode(Base.url_encode64("[1, 2]", padding: false)) == :error
    assert Report.decode(String.duplicate("a", 5000)) == :error
    assert Report.decode(nil) == :error
  end
end
