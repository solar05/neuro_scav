defmodule NeuroScavWeb.GnomeCapture do
  @moduledoc """
  Shared behaviour for handling gnome click events across LiveView modules.

  Inject via `use NeuroScavWeb.GnomeCapture`. Provides a default
  `handle_event("gnome_clicked")` implementation that increments the gnome
  capture counter and delegates to `on_gnome_clicked/1` for page-specific logic.

  ## Default behaviour

  By default, `on_gnome_clicked/1` returns `{:noreply, socket}` unchanged.
  LiveViews that need custom behaviour (e.g. updating displayed scavenger data)
  override this callback:

      def on_gnome_clicked(socket) do
        {:noreply, assign(socket, :scavenger, gnome_scavenger())}
      end
  """

  defmacro __using__(_opts) do
    quote do
      @impl true
      def handle_event("gnome_clicked", _, socket) do
        NeuroScav.StatsCounterServer.gnome_captured()
        on_gnome_clicked(socket)
      end

      def on_gnome_clicked(socket), do: {:noreply, socket}
      defoverridable on_gnome_clicked: 1
    end
  end
end
