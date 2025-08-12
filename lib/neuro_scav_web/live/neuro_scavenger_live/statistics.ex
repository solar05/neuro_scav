defmodule NeuroScavWeb.NeuroScavengerLive.Statistics do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Locale, PubSub, Scavengers}

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")

    if connected?(socket) do
      Locale.setup_locale(Map.get(session, "lang"))
      PubSub.subscribe_statistics()
    end

    user_id = Map.get(session, "user_id")

    new_socket =
      socket
      |> assign(:statistics_text, Locale.get_text("Stats placeholder"))
      |> assign(:statistics, Scavengers.get_statistics())
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    NeuroScav.StatsCounterServer.update_counter(:gnome)

    {:noreply,
     socket
     |> assign(:scavenger, Locale.get_text("Gnome catched"))}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:statistics_updated, statistics}, socket) do
    {:noreply, assign(socket, :statistics, statistics)}
  end
end
