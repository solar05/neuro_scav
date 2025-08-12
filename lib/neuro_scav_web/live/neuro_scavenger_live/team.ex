defmodule NeuroScavWeb.NeuroScavengerLive.Team do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Locale, PubSub}

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")

    if connected?(socket) do
      Locale.setup_locale(Map.get(session, "lang"))
      PubSub.subscribe(session)
    end

    user_id = Map.get(session, "user_id")

    new_socket =
      socket
      |> assign(:team, Locale.get_text("Team placeholder"))
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  # @impl true
  # def handle_event("schedule_request", _value, socket) do
  #   result =
  #     NeuroScav.UserRequestsServer.schedule_request(
  #       socket.assigns.user_id,
  #       socket.assigns.user_locale
  #     )

  #   message = format_schedule_message(result)

  #   {:noreply,
  #    socket
  #    |> assign(:scavenger, message)}
  # end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    {:noreply,
     socket
     |> assign(:scavenger, Locale.get_text("Gnome catched"))}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:scavenger_generated, msg}, socket) do
    {:noreply, assign(socket, :scavenger, msg)}
  end

  @impl true
  def handle_info(:scavenger_generation_error, socket) do
    {:noreply, assign(socket, :scavenger, Locale.get_text("Neuro error"))}
  end

  @impl true
  def handle_info({:queue_place_updated, 0}, socket) do
    {:noreply, assign(socket, :scavenger, Locale.get_text("Neuro next"))}
  end

  @impl true
  def handle_info({:queue_place_updated, place}, socket) do
    {:noreply, assign(socket, :scavenger, Locale.get_text("Queue place", place: place))}
  end
end
