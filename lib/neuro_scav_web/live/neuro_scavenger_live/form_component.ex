defmodule NeuroScavWeb.NeuroScavengerLive.FormComponent do
  use NeuroScavWeb, :live_component

  alias NeuroScav.Scavengers

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage neuro_scavenger records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="neuro_scavenger-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Neuro scavenger</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{neuro_scavenger: neuro_scavenger} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Scavengers.change_neuro_scavenger(neuro_scavenger))
     end)}
  end

  @impl true
  def handle_event("validate", %{"neuro_scavenger" => neuro_scavenger_params}, socket) do
    changeset =
      Scavengers.change_neuro_scavenger(socket.assigns.neuro_scavenger, neuro_scavenger_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"neuro_scavenger" => neuro_scavenger_params}, socket) do
    save_neuro_scavenger(socket, socket.assigns.action, neuro_scavenger_params)
  end

  defp save_neuro_scavenger(socket, :edit, neuro_scavenger_params) do
    case Scavengers.update_neuro_scavenger(socket.assigns.neuro_scavenger, neuro_scavenger_params) do
      {:ok, neuro_scavenger} ->
        notify_parent({:saved, neuro_scavenger})

        {:noreply,
         socket
         |> put_flash(:info, "Neuro scavenger updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_neuro_scavenger(socket, :new, neuro_scavenger_params) do
    case Scavengers.create_neuro_scavenger(neuro_scavenger_params) do
      {:ok, neuro_scavenger} ->
        notify_parent({:saved, neuro_scavenger})

        {:noreply,
         socket
         |> put_flash(:info, "Neuro scavenger created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
