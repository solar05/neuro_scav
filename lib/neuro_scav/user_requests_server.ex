defmodule NeuroScav.UserRequestsServer do
  @moduledoc """
  User requests server, which contains list of requests to model.
  """
  require Logger

  use GenServer

  alias NeuroScav.PubSub

  @requests_limit 10

  @spec schedule_request(String.t()) :: :scheduled | :already_scheduled
  def schedule_request(user_id) do
    GenServer.call(__MODULE__, {:add_request, user_id})
  end

  def start_link(default) when is_list(default) do
    Logger.info("User requests server started")
    schedule_server_seconds(5)
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  @impl true
  def init(requests) do
    {:ok, requests}
  end

  @impl true
  def handle_call({:add_request, user_id}, _from, state) do
    case find_request(state, user_id) do
      nil ->
        if Enum.count(state) < @requests_limit do
          new_state = state ++ [%{"user_id" => user_id, "scheduled_at" => now()}]
          {:reply, :scheduled, new_state}
        else
          {:reply, :requests_limit_reached, state}
        end

      _request ->
        Logger.info("User with id #{user_id} already scheduled request")
        {:reply, :already_scheduled, state}
    end
  end

  @impl true
  def handle_info(:process_request, []) do
    Logger.info("There is no request to execute")
    schedule_server_seconds(5)
    {:noreply, []}
  end

  @impl true
  def handle_info(:process_request, state) do
    [%{"user_id" => user_id} | new_state] = state

    Logger.info("Processing request #{user_id}")
    # add processing
    PubSub.broadcast(user_id, {:scavenger_generated, user_id})
    Logger.info("Done processing request #{user_id}")
    schedule_server_seconds(5)
    {:noreply, new_state}
  end

  defp find_request(requests, id) do
    Enum.find(requests, fn %{"user_id" => user_id} -> user_id == id end)
  end

  defp now() do
    DateTime.utc_now() |> DateTime.add(3, :hour)
  end

  defp schedule_server_seconds(time) do
    Process.send_after(__MODULE__, :process_request, :timer.seconds(time))
  end
end
