defmodule NeuroScavWeb.NeuroScavengerLive.Collection do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.Locale
  alias NeuroScav.Scavengers.Names

  @legendaries %{
    "ru" => Names.legendary_names_ru(),
    "en" => Names.legendary_names_en(),
    "de" => Names.legendary_names_de(),
    "ja" => Names.legendary_names_ja()
  }

  # the found names live in the browser's localStorage (see the Collection hook in app.js)
  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)

    {:ok,
     assign(socket,
       legendaries: Map.get(@legendaries, locale, @legendaries["ru"]),
       found: MapSet.new()
     )}
  end

  @impl true
  def handle_event("load_collection", %{"names" => names}, socket) when is_list(names) do
    found = MapSet.intersection(MapSet.new(names), MapSet.new(socket.assigns.legendaries))
    {:noreply, assign(socket, :found, found)}
  end
end
