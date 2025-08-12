defmodule NeuroScavWeb.NeuroScavengerLive.Neuro do
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
      |> assign(:neuro_scavenger, Locale.get_text("Neuro placeholder"))
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, _live_action, _params) do
    # socket
    # |> assign(:page_title, "Edit Neuro scavenger")
    # |> assign(:neuro_scavenger, Scavengers.get_neuro_scavenger!(id))
    socket
  end

  @impl true
  def handle_event("schedule_request", _value, socket) do
    result =
      NeuroScav.UserRequestsServer.schedule_request(
        socket.assigns.user_id,
        socket.assigns.user_locale
      )

    message = format_schedule_message(result)

    {:noreply,
     socket
     |> assign(:neuro_scavenger, message)}
  end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    {:noreply,
     socket
     |> assign(:neuro_scavenger, Locale.get_text("Gnome catched"))}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:scavenger_generated, msg}, socket) do
    {:noreply, assign(socket, :neuro_scavenger, msg)}
  end

  @impl true
  def handle_info(:scavenger_generation_error, socket) do
    {:noreply, assign(socket, :neuro_scavenger, Locale.get_text("Neuro error"))}
  end

  @impl true
  def handle_info({:queue_place_updated, 0}, socket) do
    {:noreply, assign(socket, :neuro_scavenger, Locale.get_text("Neuro next"))}
  end

  @impl true
  def handle_info({:queue_place_updated, place}, socket) do
    {:noreply, assign(socket, :neuro_scavenger, Locale.get_text("Queue place", place: place))}
  end

  defp format_schedule_message(result) do
    case result do
      :requests_limit_reached -> "Limit reached"
      :scheduled -> "Neuro scheduled"
      :already_scheduled -> "Neuro already scheduled"
    end
    |> Locale.get_text()
  end
end
