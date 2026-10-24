defmodule NeuroScav.UserRequestServerTest do
  alias NeuroScav.UserRequestsServer, as: Server

  use ExUnit.Case, async: false

  alias NeuroScav.{FakeClient, IncorrectFakeClient, RaisingFakeClient, SlowFakeClient}

  @user_id "12345678"
  @another_id "55555"

  @default_settings %{schedule_timer: 1, state: [], client: FakeClient}

  defp start_server(settings) do
    {:ok, pid} = GenServer.start_link(Server, settings, name: Server)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  describe "when queue is empty" do
    test "schedule request" do
      start_server(@default_settings)
      assert Server.schedule_request(@user_id, "en") == :scheduled
      assert Server.schedule_request(@user_id, "en") == :already_scheduled
      assert Server.schedule_request(@another_id, "en") == :scheduled
      assert Server.schedule_request(@another_id, "en") == :already_scheduled
      assert Server.schedule_request(@user_id, "en") == :already_scheduled
    end
  end

  describe "order and pace" do
    test "requests wait in the order they came" do
      pid = start_server(@default_settings)
      for user <- ~w(a b c d e), do: Server.schedule_request(user, "en")

      %{state: queue} = :sys.get_state(pid)
      assert Enum.map(queue, & &1["user_id"]) == ~w(a b c d e)
    end

    test "the queue takes requests while the model works on one, its user's still counting" do
      Process.register(self(), :slow_fake_client_test)
      pid = start_server(%{@default_settings | client: SlowFakeClient})
      NeuroScav.PubSub.subscribe(:neuro_scavenger, %{"user_id" => @user_id})

      Server.schedule_request(@user_id, "en")
      send(pid, :process_request)
      assert_receive {:generating, model}

      assert Server.schedule_request(@another_id, "en") == :scheduled
      assert Server.schedule_request(@user_id, "en") == :already_scheduled

      send(model, :answer)
      assert_receive {:neuro_generated, %{"name" => "Neuro Scav"}}
    end

    test "ticks by itself from the start" do
      start_server(@default_settings)
      NeuroScav.PubSub.subscribe(:neuro_scavenger, %{"user_id" => @user_id})
      Server.schedule_request(@user_id, "en")

      assert_receive {:neuro_generated, _scav}, 2_000
    end
  end

  describe "TTL expiry" do
    test "expired request is dropped without calling client" do
      pid = start_server(@default_settings)

      expired_request = %{
        "user_id" => @user_id,
        "scheduled_at" => DateTime.add(DateTime.utc_now(), -600, :second),
        "locale" => "en"
      }

      :sys.replace_state(pid, fn state -> Map.put(state, :state, [expired_request]) end)

      Process.send(pid, :process_request, [])
      _ = :sys.get_state(pid)

      %{state: queue} = :sys.get_state(pid)
      assert queue == []
      assert Process.alive?(pid)
    end

    test "fresh request is not dropped" do
      pid = start_server(@default_settings)
      Server.schedule_request(@user_id, "en")
      Process.send(pid, :process_request, [])
      _ = :sys.get_state(pid)

      %{state: queue} = :sys.get_state(pid)
      assert queue == []
      assert Process.alive?(pid)
    end
  end

  describe "client call" do
    test "when client blown up" do
      settings = %{schedule_timer: 1, state: [], client: IncorrectFakeClient}
      pid = start_server(settings)
      Server.schedule_request(@user_id, "en")
      Process.send(pid, :process_request, [])
      _ = :sys.get_state(pid)
      assert Process.alive?(pid)
    end

    test "when client raises: the user hears of an error, the queue lives on" do
      pid = start_server(%{@default_settings | client: RaisingFakeClient})
      NeuroScav.PubSub.subscribe(:neuro_scavenger, %{"user_id" => @user_id})
      Server.schedule_request(@user_id, "en")
      send(pid, :process_request)

      assert_receive :neuro_generation_error
      assert Process.alive?(pid)
    end

    test "run request" do
      pid = start_server(@default_settings)
      Server.schedule_request(@user_id, "en")
      Process.send(pid, :process_request, [])
      _ = :sys.get_state(pid)
      assert Process.alive?(pid)
    end

    test "throttle request" do
      pid = start_server(@default_settings)

      1..20
      |> Enum.each(fn user ->
        Server.schedule_request("#{user}", "en")
      end)

      Process.send(pid, :process_request, [])
      _ = :sys.get_state(pid)
      assert Process.alive?(pid)
    end

    test "when no requests" do
      pid = start_server(@default_settings)
      Process.send(pid, :process_request, [])
      _ = :sys.get_state(pid)
      assert Process.alive?(pid)
    end
  end
end
