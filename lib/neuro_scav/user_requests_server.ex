defmodule NeuroScav.UserRequestsServer do
  @moduledoc """
  User requests server, which contains list of requests to model.
  """
  require Logger

  use GenServer

  def start_link(default) when is_map(default) do
    Logger.info("User requests server started")
    GenServer.start_link(__MODULE__, default)
  end

  @impl true
  def init(requests) do
    {:ok, requests}
  end

  def handle_cast({:add_request, user_id}, _from, state) do
    new_state =
      if Map.has_key?(state, user_id) do
        Logger.info("User with id #{user_id} already scheduled request")
        state
      else
        Map.put(state, user_id, %{scheduled_at: now()})
      end

    {:noreply, new_state}
  end

  defp now() do
    DateTime.utc_now() |> DateTime.add(3, :hour)
  end
end
