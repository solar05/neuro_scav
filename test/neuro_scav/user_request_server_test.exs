defmodule NeuroScav.UserRequestServerTest do
  alias NeuroScav.UserRequestsServer, as: Server

  use ExUnit.Case, async: false

  @user_id "12345678"
  @another_id "55555"

  setup_all do
    default_settings = %{schedule_timer: -1, initial_state: []}
    {:ok, _pid} = GenServer.start_link(Server, default_settings, name: Server)
    :ok
  end

  describe "when queue is empty" do
    test "schedule request" do
      assert Server.schedule_request(@user_id) == :scheduled
      assert Server.schedule_request(@user_id) == :already_scheduled
      assert Server.schedule_request(@another_id) == :scheduled
      assert Server.schedule_request(@another_id) == :already_scheduled
      assert Server.schedule_request(@user_id) == :already_scheduled
    end
  end
end
