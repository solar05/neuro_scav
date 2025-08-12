defmodule NeuroScav.ScavengersServer do
  @moduledoc """
  Statistics counter server.
  """
  require Logger

  use GenServer

  alias NeuroScav.Scavengers.Names
  alias NeuroScav.PubSub

  @max_team_members 5

  @spec generate_single(String.t(), String.t()) :: :ok
  def generate_single(user_id, locale \\ "en") do
    GenServer.cast(__MODULE__, {:generate_single, user_id, locale})
  end

  def generate_team(user_id, locale \\ "en") do
    GenServer.cast(__MODULE__, {:generate_team, user_id, locale})
  end

  def start_link(_settings) do
    GenServer.start_link(
      __MODULE__,
      %{},
      name: __MODULE__
    )
  end

  @impl true
  def init(_default_state) do
    state = %{
      "first_names_ru" => Names.first_names_ru(),
      "last_names_ru" => Names.last_names_ru(),
      "first_names_en" => Names.first_names_en(),
      "last_names_en" => Names.last_names_en(),
      "legendary_names_ru" => Names.legendary_names_ru(),
      "legendary_names_en" => Names.legendary_names_en()
    }

    Logger.info("Scavenger server started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:generate_single, user_id, locale}, state) do
    scavenger = generate_scavenger(state, locale)
    PubSub.broadcast(user_id, {:single_generated, :single_scavenger, scavenger})

    {:noreply, state}
  end

  def handle_cast({:generate_team, user_id, locale}, state) do
    team = 1..@max_team_members |> Enum.map(fn _ -> generate_scavenger(state, locale) end)

    PubSub.broadcast(user_id, {:team_generated, :team_scavengers, team})

    {:noreply, state}
  end

  defp generate_scavenger(names, locale) do
    first_name =
      Map.get(names, "first_names_#{locale}") |> Enum.random()

    last_name =
      Map.get(names, "last_names_#{locale}") |> Enum.random()

    name = "#{first_name} #{last_name}"

    rarity =
      cond do
        legendary?(names, name, locale) == true -> :legendary
        epic?(name) == true -> :epic
        rare?(name) == true -> :rare
        uncommon?(name) == true -> :uncommon
        true -> :common
      end

    NeuroScav.StatsCounterServer.update_counter(rarity)

    %{name: name, rarity: rarity}
  end

  defp legendary?(names, name, locale) do
    Map.get(names, "legendary_names_#{locale}") |> Enum.member?(name)
  end

  defp epic?(name) do
    [first_name, last_name] = String.split(name, " ")
    String.slice(first_name, -3..-1) == String.slice(last_name, -3..-1)
  end

  defp rare?(name) do
    [first_name, last_name] = String.split(name, " ")
    String.first(first_name) == String.first(last_name)
  end

  defp uncommon?(name) do
    [first_name, last_name] = String.split(name, " ")
    String.length(first_name) == String.length(last_name)
  end
end
