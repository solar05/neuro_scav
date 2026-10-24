defmodule NeuroScavWeb.NeuroScavengerLive.Statistics do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{Locale, PubSub, Scavengers}
  alias NeuroScavWeb.RaidComponents

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
      |> assign(:raid_statistics, Scavengers.list_raid_statistics())
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:statistics_updated, statistics}, socket) do
    {:noreply, assign(socket, :statistics, statistics)}
  end

  def handle_info({:raid_statistics_updated, raid_statistics}, socket) do
    {:noreply, assign(socket, :raid_statistics, raid_statistics)}
  end

  # every location together
  defp raid_total(rows) do
    for key <- [:raids, :wiped, :members, :survivors], into: %{} do
      {key, rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()}
    end
  end

  defp percent(_part, 0), do: "—"
  defp percent(part, total), do: "#{round(part * 100 / total)}%"
end
