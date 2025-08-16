defmodule NeuroScav.UserRequestServerTest do
  alias NeuroScav.UserRequestsServer, as: Server

  use ExUnit.Case, async: true

  alias NeuroScav.{FakeClient, IncorrectFakeClient}

  @user_id "12345678"
  @another_id "55555"

  @default_settings %{schedule_timer: 1, state: [], client: FakeClient}

  describe "when queue is empty" do
    test "schedule request" do
      Process.sleep(100)
      {:ok, _pid} = GenServer.start_link(Server, @default_settings, name: Server)
      assert Server.schedule_request(@user_id, "en") == :scheduled
      assert Server.schedule_request(@user_id, "en") == :already_scheduled
      assert Server.schedule_request(@another_id, "en") == :scheduled
      assert Server.schedule_request(@another_id, "en") == :already_scheduled
      assert Server.schedule_request(@user_id, "en") == :already_scheduled
    end
  end

  describe "client call" do
    test "when client blown up" do
      Process.sleep(100)
      settings = %{schedule_timer: 1, state: [], client: IncorrectFakeClient}
      {:ok, pid} = GenServer.start_link(Server, settings, name: Server)
      Server.schedule_request(@user_id, "en")
      Process.send(pid, :process_request, [])
      Process.sleep(100)

      assert Process.alive?(pid)
    end

    test "run request" do
      Process.sleep(100)
      {:ok, pid} = GenServer.start_link(Server, @default_settings, name: Server)
      Server.schedule_request(@user_id, "en")
      Process.send(pid, :process_request, [])
      assert Process.alive?(pid)
    end

    test "throttle request" do
      Process.sleep(100)
      {:ok, pid} = GenServer.start_link(Server, @default_settings, name: Server)

      1..20
      |> Enum.map(fn user ->
        Server.schedule_request("#{user}", "en")
      end)

      Process.send(pid, :process_request, [])
      Process.sleep(100)
    end

    test "when no requests" do
      Process.sleep(100)
      {:ok, pid} = GenServer.start_link(Server, @default_settings, name: Server)
      Process.send(pid, :process_request, [])
      assert Process.alive?(pid)
    end
  end
end
