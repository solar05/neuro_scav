defmodule NeuroScavWeb.NeuroScavengerLive.Index do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Scavengers, Pubsub}

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      setup_locale(Map.get(session, "lang"))
      Pubsub.subscribe(session)
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
    Pubsub.broadcast(socket.assigns.user_id, {:lala, "jopa"})

    socket
    |> assign(:page_title, "New Neuro scavenger")
    # add loading logic
    |> assign(:scavenger, "Wait")
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

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    neuro_scavenger = Scavengers.get_neuro_scavenger!(id)
    {:ok, _} = Scavengers.delete_neuro_scavenger(neuro_scavenger)

    {:noreply, stream_delete(socket, :neuro_scavengers, neuro_scavenger)}
  end

  # pubsub callbacks
  def handle_info(_msg, socket) do
    # add logic for completed request
    {:noreply, assign(socket, :scavenger, "New scav #{Enum.random(1..30)}")}
  end

  defp setup_locale(locale) do
    NeuroScavWeb.Plugs.SetLocale.put_gettext_locale(locale)
  end

  defp placeholder() do
    Gettext.gettext(NeuroScavWeb.Gettext, "Neuro placeholder")
  end
end
