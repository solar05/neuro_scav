defmodule NeuroScav.StatsCounterServerTest do
  alias NeuroScav.StatsCounterServer, as: Server

  use ExUnit.Case, async: false
  use NeuroScav.DataCase

  import NeuroScav.ScavengersFixtures

  setup do
    default_settings = statistics_fixture()
    {:ok, _pid} = GenServer.start_link(Server, default_settings, name: Server)
    :ok
  end

  describe "update_counter/1" do
    test "updates available counters correctly" do
      Server.available_counters()
      |> Enum.map(fn counter ->
        assert Server.update_counter(counter) == :ok
      end)

      assert %{common: 1, uncommon: 1, rare: 1, epic: 1, legendary: 1, neuro: 1, gnome: 1} =
               Process.whereis(Server) |> :sys.get_state()
    end

    test "does not update incorrect counter" do
      assert Server.update_counter(:something_strange) == :invalid_counter
    end
  end

  describe "gnome_captured/0" do
    test "updates gnome stat correctly" do
      assert Server.gnome_captured() == :ok

      assert %{gnome: 1} = Process.whereis(Server) |> :sys.get_state()
    end
  end

  describe "update_miltiple_counters/1" do
    test "updates stats correctly" do
      data = [:common, :rare, :gnome, :gnome, :common, :legendary]
      assert Server.update_miltiple_counters(data) == :ok

      assert %{gnome: 2, common: 2, legendary: 1} = Process.whereis(Server) |> :sys.get_state()
    end

    test "does not update incorrect counters" do
      assert Server.update_miltiple_counters([:ultra_rare_gnome]) == :invalid_counter
    end

    test "does not update empty counters" do
      assert Server.update_miltiple_counters([]) == :invalid_counter
    end
  end
end
