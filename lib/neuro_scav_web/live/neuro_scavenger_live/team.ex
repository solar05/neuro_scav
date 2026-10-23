defmodule NeuroScavWeb.NeuroScavengerLive.Team do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{Locale, PubSub, ScavengersServer}

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")

    if connected?(socket) do
      Locale.setup_locale(Map.get(session, "lang"))
      PubSub.subscribe(:team_scavengers, session)
    end

    user_id = Map.get(session, "user_id")

    new_socket =
      socket
      |> assign(:team, [])
      |> assign(:locked, MapSet.new())
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  @impl true
  def handle_event("generate_team", _value, socket) do
    %{user_id: user_id, user_locale: locale, locked: locked} = socket.assigns
    count = ScavengersServer.max_team_members() - MapSet.size(locked)
    if count > 0, do: ScavengersServer.generate_team(user_id, locale, count)

    {:noreply, socket}
  end

  def handle_event("toggle_lock", %{"index" => index}, socket) do
    index = String.to_integer(index)
    %{locked: locked, team: team} = socket.assigns

    locked =
      cond do
        index in locked -> MapSet.delete(locked, index)
        index in 0..(length(team) - 1)//1 -> MapSet.put(locked, index)
        true -> locked
      end

    {:noreply, assign(socket, :locked, locked)}
  end

  def on_gnome_clicked(socket),
    do: {:noreply, assign(socket, team: gnome_team(), locked: MapSet.new())}

  defp team_sets(team), do: team |> Enum.map(& &1.name) |> ScavengersServer.team_sets()
  defp set_label(set), do: Locale.get_text("Set #{set}")

  # pubsub callbacks
  @impl true
  def handle_info({:team_generated, fresh}, socket) do
    {:noreply, assign(socket, :team, refill(socket.assigns.team, fresh, socket.assigns.locked))}
  end

  # Locked slots keep their member, the others take fresh ones in order.
  defp refill([], fresh, _locked), do: fresh

  defp refill(team, fresh, locked) do
    {team, _unused} =
      team
      |> Enum.with_index()
      |> Enum.map_reduce(fresh, fn
        {member, index}, [next | rest] = fresh ->
          if MapSet.member?(locked, index), do: {member, fresh}, else: {next, rest}

        {member, _index}, [] ->
          {member, []}
      end)

    team
  end

  defp slots(team),
    do: Enum.map(0..(ScavengersServer.max_team_members() - 1), &{&1, Enum.at(team, &1)})

  defp slot_style(0), do: "border-radius: 10px 10px 0px 0px;"
  defp slot_style(4), do: "border-radius: 0px 0px 10px 10px; border-bottom: none;"
  defp slot_style(_), do: nil

  defp gnome_team do
    1..ScavengersServer.max_team_members()
    |> Enum.map(fn _ ->
      %{
        name: Locale.get_text("Gnome catched"),
        rarity: "gnome",
        rarity_text: Locale.get_text("gnome")
      }
    end)
  end
end
