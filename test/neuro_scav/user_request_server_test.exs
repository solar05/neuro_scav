defmodule NeuroScav.UserRequestServerTest do
  alias NeuroScav.UserRequestsServer, as: Server

  use ExUnit.Case, async: false

  alias NeuroScav.{FakeClient, IncorrectFakeClient}

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
