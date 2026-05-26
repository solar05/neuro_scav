defmodule NeuroScavWeb.NeuroScavengerLive.Glossary do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.Locale

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)
    {:ok, socket}
  end
end
