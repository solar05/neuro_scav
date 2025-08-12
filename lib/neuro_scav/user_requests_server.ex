defmodule NeuroScav.UserRequestsServer do
  @moduledoc """
  User requests server, which contains list of requests to model.
  """
  require Logger

  use GenServer

  alias NeuroScav.{Client, PubSub}
  alias PromEx.Plugins.NeuroScav, as: NeuroPromex

  @requests_limit 10

  @spec schedule_request(String.t(), String.t()) ::
          :scheduled | :already_scheduled | :requests_limit_reached
  def schedule_request(user_id, locale) do
    GenServer.call(__MODULE__, {:add_request, user_id, locale})
  end

  def start_link(%{schedule_timer: schedule_timer, initial_state: default_state} = settings)
      when is_map(settings) do
    schedule_server_seconds(schedule_timer)

    GenServer.start_link(
      __MODULE__,
      %{schedule_timer: schedule_timer, initial_state: default_state},
      name: __MODULE__
    )
  end

  @impl true
  def init(%{initial_state: default_state}) do
    Logger.info("User requests server started")
    {:ok, default_state}
  end

  @impl true
  def handle_call({:add_request, user_id, locale}, _from, state) do
    case find_request(state, user_id) do
      nil ->
        if Enum.count(state) < @requests_limit do
          new_state =
            state ++ [%{"user_id" => user_id, "scheduled_at" => now(), "locale" => locale}]

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
    [%{"user_id" => user_id, "locale" => locale} | new_state] = state

    Logger.info("Processing request #{user_id}")
    notify_user_places(user_id)

    {exec_time, _} =
      :timer.tc(fn ->
        case Client.generate_scav(Client.init(), locale) do
          {:ok, result} ->
            PubSub.broadcast(user_id, {:scavenger_generated, :neuro_scavenger, result})
            notify_user_places(new_state)

          {:error, _} ->
            PubSub.broadcast(user_id, {:scavenger_generation_error, :neuro_scavenger})
            notify_user_places(new_state)
        end
      end)

    formatted_exec_time = format_exec_time(exec_time)
    export_request_processed_info(formatted_exec_time)
    Logger.info("Done processing request #{user_id} about #{formatted_exec_time / 1000} seconds")
    schedule_server_seconds(2)
    {:noreply, new_state}
  end

  defp find_request(requests, id) do
    Enum.find(requests, fn %{"user_id" => user_id} -> user_id == id end)
  end

  defp now do
    DateTime.utc_now() |> DateTime.add(3, :hour)
  end

  defp schedule_server_seconds(-1), do: nil

  defp schedule_server_seconds(time) do
    Process.send_after(__MODULE__, :process_request, :timer.seconds(time))
  end

  defp notify_user_places(user_id) when is_binary(user_id) do
    PubSub.broadcast(user_id, {:queue_place_updated, :neuro_scavenger, 0})
  end

  defp notify_user_places(users) when is_list(users) do
    Enum.reduce(users, 1, fn %{"user_id" => user_id}, acc ->
      PubSub.broadcast(user_id, {:queue_place_updated, :neuro_scavenger, acc})
      acc + 1
    end)
  end

  defp export_request_processed_info(exec_time) do
    :telemetry.execute(
      NeuroPromex.processed_request_measure(),
      %{duration: exec_time},
      %{}
    )

    :telemetry.execute(NeuroPromex.processed_request_count(), %{}, %{})
  end

  defp format_exec_time(0), do: 0
  defp format_exec_time(exec_time), do: exec_time / 1_000
end
