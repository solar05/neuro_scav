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

  describe "restarts and failures" do
    test "a restarted server picks up every count so far, nothing is written over" do
      for _ <- 1..5, do: Server.update_counter(:common)
      _ = :sys.get_state(Server)

      # the supervisor's way: a restart with the argument the server first had
      pid = Process.whereis(Server)
      first = :sys.get_state(pid)
      ref = Process.monitor(pid)
      # started from setup: linked to the test, which mustn't go down with it
      Process.unlink(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, _, _, _}
      {:ok, _pid} = GenServer.start_link(Server, %{first | common: 0}, name: Server)

      Server.update_counter(:common)
      assert %{common: 6} = :sys.get_state(Server)
      assert NeuroScav.Scavengers.get_statistics(first.id).common == 6
    end

    test "a count that can't be written is lost, the server goes on" do
      :sys.replace_state(Server, &%{&1 | id: -1})
      assert Server.update_counter(:rare) == :ok

      assert %{id: -1, rare: 0} = :sys.get_state(Server)
      assert Process.alive?(Process.whereis(Server))
    end
  end

  describe "update_multiple_counters/1" do
    test "updates stats correctly" do
      data = [:common, :rare, :gnome, :gnome, :common, :legendary]
      assert Server.update_multiple_counters(data) == :ok

      assert %{gnome: 2, common: 2, legendary: 1} = Process.whereis(Server) |> :sys.get_state()
    end

    test "does not update incorrect counters" do
      assert Server.update_multiple_counters([:ultra_rare_gnome]) == :invalid_counter
    end

    test "does not update empty counters" do
      assert Server.update_multiple_counters([]) == :invalid_counter
    end
  end
end
