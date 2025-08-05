defmodule NeuroScavWeb.NeuroScavengerLive.Show do
  use NeuroScavWeb, :live_view

  alias NeuroScav.Scavengers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:neuro_scavenger, Scavengers.get_neuro_scavenger!(id))}
  end

  defp page_title(:show), do: "Show Neuro scavenger"
  defp page_title(:edit), do: "Edit Neuro scavenger"
end
