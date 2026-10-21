defmodule NeuroScavWeb.LegendaryToast do
  @moduledoc """
  Shows a toast on every LiveView page when someone else rolls a legendary.

  Mounted into all LiveViews by `NeuroScavWeb.live_view/0`. The finder's own
  pages skip it: they already get the confetti.
  """

  use Gettext, backend: NeuroScavWeb.Gettext

  import Phoenix.LiveView

  alias NeuroScav.PubSub

  def on_mount(:default, _params, session, socket) do
    if connected?(socket) do
      PubSub.subscribe_finds()
      user_id = Map.get(session, "user_id")
      {:cont, attach_hook(socket, :legendary_toast, :handle_info, &handle_find(&1, &2, user_id))}
    else
      {:cont, socket}
    end
  end

  defp handle_find({:legendary_found, %{user_id: user_id}}, socket, user_id)
       when is_binary(user_id),
       do: {:halt, socket}

  defp handle_find({:legendary_found, %{name: name}}, socket, _user_id) do
    text = gettext("Someone found legendary %{name}", name: name)
    {:halt, push_event(socket, "legendary-found", %{text: text})}
  end

  defp handle_find(_message, socket, _user_id), do: {:cont, socket}
end
