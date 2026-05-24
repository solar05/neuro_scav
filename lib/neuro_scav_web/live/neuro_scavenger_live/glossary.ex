defmodule NeuroScavWeb.NeuroScavengerLive.Glossary do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Locale, StatsCounterServer}

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)
    {:ok, socket}
  end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    StatsCounterServer.gnome_captured()
    {:noreply, socket}
  end
end
