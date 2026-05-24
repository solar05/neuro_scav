defmodule NeuroScavWeb.NeuroScavengerLive.Single do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Locale, PubSub, StatsCounterServer}

  @streak_rarities [:uncommon, :rare, :epic, :legendary, :neuro, "gnome"]

  @gnome_probability 3

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
      |> assign(:streak, 0)
      |> assign(:streak_class, "streak-warm")
      |> assign(:gnome_lurking, false)

    {:ok, new_socket}
  end

  @impl true
  def handle_event("generate_single", _value, socket) do
    NeuroScav.ScavengersServer.generate_single(socket.assigns.user_id, socket.assigns.user_locale)

    {:noreply, assign(socket, :gnome_lurking, false)}
  end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    StatsCounterServer.gnome_captured()

    {:noreply,
     socket
     |> assign(:scavenger, %{
       name: Locale.get_text("Gnome catched"),
       rarity: "gnome",
       rarity_text: Locale.get_text("gnome")
     })
     |> assign(:gnome_lurking, false)
     |> update_streak("gnome")}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:single_generated, %{rarity: rarity, name: name}}, socket) do
    rarity_text = Locale.get_text(Atom.to_string(rarity))
    gnome_lurking = :rand.uniform(100) <= @gnome_probability

    {:noreply,
     socket
     |> assign(:scavenger, %{name: name, rarity: rarity, rarity_text: rarity_text})
     |> assign(:gnome_lurking, gnome_lurking)
     |> update_streak(rarity)}
  end

  defp update_streak(socket, rarity) when rarity in @streak_rarities do
    new_streak = socket.assigns.streak + 1

    socket
    |> assign(:streak, new_streak)
    |> assign(:streak_class, streak_css_class(new_streak))
  end

  defp update_streak(socket, _common) do
    socket
    |> assign(:streak, 0)
    |> assign(:streak_class, "streak-warm")
  end

  defp streak_css_class(n) when n >= 10, do: "streak-legendary"
  defp streak_css_class(n) when n >= 5, do: "streak-hot"
  defp streak_css_class(_), do: "streak-warm"
end
