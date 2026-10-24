defmodule NeuroScavWeb.GnomeCapture do
  @moduledoc """
  Shared behaviour for handling gnome click events across LiveView modules.

  Inject via `use NeuroScavWeb.GnomeCapture`. Provides a default
  `handle_event("gnome_clicked")` implementation that increments the gnome
  capture counter and delegates to `on_gnome_clicked/1` for page-specific logic.

  When the gnome shows is the browser's call (`assets/js/gnome.js`), so the
  server only takes a page's capture at most every `@gap_ms`, the shortest
  wait between two appearances: a faster one is a crafted event, not a catch,
  and it neither counts nor gives the page its gnome.

  ## Default behaviour

  By default, `on_gnome_clicked/1` returns `{:noreply, socket}` unchanged.
  LiveViews that need custom behaviour (e.g. updating displayed scavenger data)
  override this callback:

      def on_gnome_clicked(socket) do
        {:noreply, assign(socket, :scavenger, gnome_scavenger())}
      end
  """

  # ponytail: per page, so many pages at once each catch one; a server-chosen
  # appearance (a token sent with the gnome) would close that too

  # gnome.js waits 1 × 10 s at the least before the gnome shows again
  @gap_ms 10_000

  defmacro __using__(_opts) do
    quote do
      @impl true
      def handle_event("gnome_clicked", _, socket),
        do: NeuroScavWeb.GnomeCapture.capture(socket, &on_gnome_clicked/1)

      def on_gnome_clicked(socket), do: {:noreply, socket}
      defoverridable on_gnome_clicked: 1
    end
  end

  @doc "A page's capture, counted and handed to `on_caught`, unless it's sooner than the gnome can be back."
  @spec capture(Phoenix.LiveView.Socket.t(), (Phoenix.LiveView.Socket.t() -> term())) :: term()
  def capture(socket, on_caught) do
    now = System.monotonic_time(:millisecond)
    last = socket.assigns[:gnome_caught_at]

    if last && now - last < @gap_ms do
      {:noreply, socket}
    else
      NeuroScav.StatsCounterServer.gnome_captured()
      socket |> Phoenix.Component.assign(:gnome_caught_at, now) |> on_caught.()
    end
  end
end
