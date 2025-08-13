defmodule NeuroScavWeb.NeuroScavengerLive.Team do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Locale, PubSub, StatsCounterServer}

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
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  def handle_event("generate_team", _value, socket) do
    NeuroScav.ScavengersServer.generate_team(socket.assigns.user_id, socket.assigns.user_locale)

    {:noreply, socket}
  end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    StatsCounterServer.gnome_captured()

    {:noreply, socket}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:team_generated, team}, socket) do
    {:noreply, assign(socket, :team, team)}
  end
end
