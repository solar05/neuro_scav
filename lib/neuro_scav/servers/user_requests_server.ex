defmodule NeuroScav.UserRequestsServer do
  @moduledoc """
  The queue of Neuro requests to the model (Ollama): one at a time, the
  oldest first, a tick every `schedule_timer` seconds; a user has one request
  in it at most, and the queue holds `@requests_limit`.

  The model may take a minute to answer, so it's waited for in a task: the
  queue goes on taking requests meanwhile, and the next tick comes once the
  answer is in. The request in work is still its user's (`:already_scheduled`).
  A request older than `@request_ttl_seconds` is dropped unprocessed.
  """
  require Logger

  use GenServer

  alias NeuroScav.PubSub
  alias PromEx.Plugins.NeuroScav, as: NeuroPromex

  @requests_limit 10
  # Requests older than this are dropped without processing
  @request_ttl_seconds 300

  @spec schedule_request(String.t(), String.t()) ::
          :scheduled | :already_scheduled | :requests_limit_reached
  def schedule_request(user_id, locale) do
    GenServer.call(__MODULE__, {:add_request, user_id, locale}, :timer.seconds(30))
  end

  def start_link(%{schedule_timer: _seconds, state: _queue, client: _client} = settings),
    do: GenServer.start_link(__MODULE__, settings, name: __MODULE__)

  # the first tick from here, to this very process: a restarted server starts
  # one chain of ticks afresh, the old one's ticks die with it
  @impl true
  def init(settings) do
    Logger.info("User requests server started")
    {:ok, settings |> Map.merge(%{processing: nil, timer: nil}) |> schedule()}
  end

  @impl true
  def handle_call({:add_request, user_id, locale}, _from, %{state: state} = settings) do
    cond do
      scheduled?(settings, user_id) ->
        Logger.info("User with id #{user_id} already scheduled request")
        {:reply, :already_scheduled, settings}

      Enum.count(state) < @requests_limit ->
        request = %{"user_id" => user_id, "scheduled_at" => now(), "locale" => locale}
        {:reply, :scheduled, %{settings | state: state ++ [request]}}

      true ->
        {:reply, :requests_limit_reached, settings}
    end
  end

  # a tick while the model works on a request: the answer brings the next one
  @impl true
  def handle_info(:process_request, %{processing: %{}} = settings), do: {:noreply, settings}

  def handle_info(:process_request, %{state: []} = settings) do
    # every tick of an empty queue: info would flood the log
    Logger.debug("There is no request to execute")
    {:noreply, schedule(settings)}
  end

  def handle_info(
        :process_request,
        %{state: [%{"user_id" => user_id} = request | rest]} = settings
      ) do
    if expired?(request) do
      Logger.info("Dropping expired request for user #{user_id}")
      PubSub.broadcast(user_id, {:neuro_generation_error, :neuro_scavenger})
      notify_user_places(rest)
      {:noreply, schedule(%{settings | state: rest})}
    else
      {:noreply, start(request, %{settings | state: rest})}
    end
  end

  # the model's answer to the request in work
  def handle_info({ref, result}, %{processing: %{ref: ref} = processing} = settings) do
    Process.demonitor(ref, [:flush])
    %{request: %{"user_id" => user_id}, started: started} = processing

    case result do
      {:ok, scav} ->
        NeuroScav.StatsCounterServer.update_counter(:neuro)
        PubSub.broadcast(user_id, {:neuro_generated, :neuro_scavenger, scav})

      _error ->
        PubSub.broadcast(user_id, {:neuro_generation_error, :neuro_scavenger})
    end

    notify_user_places(settings.state)
    exec_time = format_exec_time(System.monotonic_time(:microsecond) - started)
    export_request_processed_info(exec_time)
    Logger.info("Done processing request #{user_id} about #{exec_time / 1000} seconds")
    {:noreply, schedule(%{settings | processing: nil})}
  end

  defp start(%{"user_id" => user_id, "locale" => locale} = request, %{client: client} = settings) do
    Logger.info("Processing request #{user_id}")
    notify_user_places(user_id)
    task = Task.async(fn -> generate(client, locale) end)
    started = System.monotonic_time(:microsecond)
    %{settings | processing: %{ref: task.ref, request: request, started: started}}
  end

  # whatever goes wrong with the model is the request's error, not the queue's crash
  defp generate(client, locale) do
    client.generate_scav(locale)
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  # the next tick, the pending one (if any) put off: one chain of ticks at a time
  defp schedule(%{timer: timer, schedule_timer: seconds} = settings) do
    if timer, do: Process.cancel_timer(timer)
    %{settings | timer: Process.send_after(self(), :process_request, :timer.seconds(seconds))}
  end

  # waiting in the queue, or being worked on
  defp scheduled?(%{state: state, processing: processing}, user_id) do
    Enum.any?(state, &(&1["user_id"] == user_id)) or
      match?(%{request: %{"user_id" => ^user_id}}, processing)
  end

  defp now, do: DateTime.utc_now()

  @spec expired?(map()) :: boolean()
  defp expired?(%{"scheduled_at" => scheduled_at}) do
    DateTime.diff(DateTime.utc_now(), scheduled_at, :second) > @request_ttl_seconds
  end

  defp expired?(_), do: false

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

  defp format_exec_time(exec_time), do: exec_time / 1_000
end
