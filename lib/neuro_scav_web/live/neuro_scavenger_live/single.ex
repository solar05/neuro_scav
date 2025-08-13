defmodule NeuroScavWeb.NeuroScavengerLive.Single do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Locale, PubSub, StatsCounterServer}

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")

    if connected?(socket) do
      Locale.setup_locale(locale)
      PubSub.subscribe(:single_scavenger, session)
    end

    user_id = Map.get(session, "user_id")

    new_socket =
      socket
      |> assign(:scavenger, %{
        name: Locale.get_text("Single placeholder"),
        rarity: nil,
        rarity_text: Locale.get_text("default")
      })
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  @impl true
  def handle_event("generate_single", _value, socket) do
    NeuroScav.ScavengersServer.generate_single(socket.assigns.user_id, socket.assigns.user_locale)

    {:noreply, socket}
  end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    StatsCounterServer.gnome_captured()

    {:noreply,
     socket
     |> assign(:scavenger, %{
       name: Locale.get_text("Gnome catched"),
       rarity: nil,
       rarity_text: Locale.get_text("gnome")
     })}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:single_generated, %{rarity: rarity, name: name}}, socket) do
    rarity_text = Locale.get_text(Atom.to_string(rarity))

    {:noreply,
     assign(socket, :scavenger, %{name: name, rarity: rarity, rarity_text: rarity_text})}
  end
end
