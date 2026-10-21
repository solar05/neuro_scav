defmodule NeuroScavWeb.NeuroScavengerLive.Glossary do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{Locale, ScavengersServer}
  alias NeuroScav.Scavengers.Names

  # Walks every name pair (seconds of work), so it runs once at compile time
  @odds Map.new(~w(ru en de ja), &{&1, ScavengersServer.odds(Names, &1)})

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)
    {:ok, assign(socket, :odds, Map.get(@odds, locale, @odds["ru"]))}
  end

  defp chance(odds, rarity) do
    percent = Map.get(odds, rarity, 0.0)
    decimals = if percent >= 1, do: 1, else: 3
    :erlang.float_to_binary(percent, [:compact, decimals: decimals]) <> "%"
  end
end
