defmodule NeuroScavWeb.OnlineCounter do
  @moduledoc """
  Counts users online for the badge in the app layout.

  Mounted into all LiveViews by `NeuroScavWeb.live_view/0`. Every connected
  page is tracked under its user id, so several tabs of one user count once.
  `@online_count` is nil until the socket connects: the dead render isn't
  tracked yet and would show one user too few.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias NeuroScavWeb.Presence

  @topic "online"

  def on_mount(:default, _params, session, socket) do
    if connected?(socket) do
      {:ok, _ref} = Presence.track(self(), @topic, Map.fetch!(session, "user_id"), %{})
      Phoenix.PubSub.subscribe(NeuroScav.PubSub, @topic)

      {:cont,
       socket
       |> assign(:online_count, count())
       |> attach_hook(:online_counter, :handle_info, &handle_diff/2)}
    else
      {:cont, assign(socket, :online_count, nil)}
    end
  end

  # ponytail: every page recounts on every join/leave — fine for hundreds online;
  # beyond that, count in one process and broadcast the number instead
  defp handle_diff(%Phoenix.Socket.Broadcast{topic: @topic, event: "presence_diff"}, socket),
    do: {:halt, assign(socket, :online_count, count())}

  defp handle_diff(_message, socket), do: {:cont, socket}

  defp count, do: @topic |> Presence.list() |> map_size()
end
