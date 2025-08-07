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

    new_socket =
      socket
      |> assign(:scavenger, placeholder())
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Neuro scavenger")
    |> assign(:neuro_scavenger, Scavengers.get_neuro_scavenger!(id))
  end

  defp apply_action(socket, :new, _params) do
    result = NeuroScav.UserRequestsServer.schedule_request(socket.assigns.user_id)
    message = format_schedule_message(result)

    socket
    |> assign(:page_title, "New Neuro scavenger")
    |> assign(:scavenger, message)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Neuro scavengers")
    |> assign(:neuro_scavenger, nil)
  end

  @impl true
  def handle_info(
        {NeuroScavWeb.NeuroScavengerLive.FormComponent, {:saved, neuro_scavenger}},
        socket
      ) do
    {:noreply, stream_insert(socket, :neuro_scavengers, neuro_scavenger)}
  end

  # pubsub callbacks
  def handle_info({:scavenger_generated, msg}, socket) do
    # add logic for completed request
    {:noreply, assign(socket, :scavenger, "New scav #{msg}")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    neuro_scavenger = Scavengers.get_neuro_scavenger!(id)
    {:ok, _} = Scavengers.delete_neuro_scavenger(neuro_scavenger)

    {:noreply, stream_delete(socket, :neuro_scavengers, neuro_scavenger)}
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
