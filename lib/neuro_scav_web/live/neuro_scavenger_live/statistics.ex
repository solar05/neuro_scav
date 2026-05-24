defmodule NeuroScavWeb.NeuroScavengerLive.Statistics do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Locale, PubSub, Scavengers, StatsCounterServer}

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")

    if connected?(socket) do
      Locale.setup_locale(Map.get(session, "lang"))
      PubSub.subscribe_statistics()
    end

    statistics = Scavengers.get_statistics()
    user_id = Map.get(session, "user_id")

    new_socket =
      socket
      |> assign(:statistics, statistics)
      |> assign(:total, compute_total(statistics))
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    StatsCounterServer.gnome_captured()

    {:noreply, socket}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:statistics_updated, statistics}, socket) do
    {:noreply,
     socket
     |> assign(:statistics, statistics)
     |> assign(:total, compute_total(statistics))}
  end

  defp compute_total(nil), do: 0

  defp compute_total(stats) do
    stats.common + stats.uncommon + stats.rare + stats.epic +
      stats.legendary + stats.neuro + stats.gnome
  end

  def calc_percent(_count, 0), do: "–"

  def calc_percent(count, total) do
    pct = Float.round(count / total * 100, 1)
    "#{pct}%"
  end
end
