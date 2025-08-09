defmodule NeuroScavWeb.NeuroScavengerLive.Index do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Scavengers, PubSub}

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      setup_locale(Map.get(session, "lang"))
      PubSub.subscribe(session)
    end

    user_id = Map.get(session, "user_id")
    locale = Map.get(session, "lang")

    new_socket =
      socket
      |> assign(:scavenger, placeholder())
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

  def handle_event("schedule_request", _value, socket) do
    result =
      NeuroScav.UserRequestsServer.schedule_request(
        socket.assigns.user_id,
        socket.assigns.user_locale
      )

    message = format_schedule_message(result)

    {:noreply,
     socket
     |> assign(:page_title, "New Neuro scavenger")
     |> assign(:scavenger, message)}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:scavenger_generated, msg}, socket) do
    {:noreply, assign(socket, :scavenger, msg)}
  end

  @impl true
  def handle_info(:scavenger_generation_error, socket) do
    {:noreply, assign(socket, :scavenger, get_text("Neuro error"))}
  end

  defp setup_locale(locale) do
    NeuroScavWeb.Plugs.SetLocale.put_gettext_locale(locale)
  end

  defp get_text(msg) do
    Gettext.gettext(NeuroScavWeb.Gettext, msg)
  end

  defp placeholder() do
    get_text("Neuro placeholder")
  end

  defp format_schedule_message(result) do
    case result do
      :requests_limit_reached ->
        get_text("Limit reached")

      :scheduled ->
        get_text("Neuro scheduled")

      :already_scheduled ->
        get_text("Neuro already scheduled")
    end
  end
end
