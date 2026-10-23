defmodule NeuroScavWeb.NeuroScavengerLive.Glossary do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{BattleRoom, Locale, ScavengersServer}
  alias NeuroScav.Scavengers.Names

  # Walks every name pair (seconds of work), so it runs once at compile time
  @odds Map.new(~w(ru en de ja), fn locale ->
          odds = ScavengersServer.odds(Names, locale)
          {locale, Map.put(odds, :gnome, 100 / ScavengersServer.gnome_odds())}
        end)

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)
    {:ok, assign(socket, :odds, Map.get(@odds, locale, @odds["ru"]))}
  end

  defp set_label(set), do: Locale.get_text("Set #{set}")
  defp set_rule(set), do: Locale.get_text("Set #{set} rule")

  # rounded outer corners, like the rarity table
  defp set_cell_style(0, :name), do: "border-radius: 10px 0px 0px 0px; width: 36%;"
  defp set_cell_style(0, :rule), do: "border-radius: 0px 10px 0px 0px;"
  defp set_cell_style(2, :name), do: "border-radius: 0px 0px 0px 10px; border-bottom: none;"
  defp set_cell_style(2, :rule), do: "border-radius: 0px 0px 10px 0px; border-bottom: none;"
  defp set_cell_style(_row, _cell), do: nil

  defp chance(odds, rarity) do
    percent = Map.get(odds, rarity, 0.0)
    decimals = if percent >= 1, do: 1, else: 3
    :erlang.float_to_binary(percent, [:compact, decimals: decimals]) <> "%"
  end
end
