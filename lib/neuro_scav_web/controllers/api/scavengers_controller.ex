defmodule NeuroScavWeb.Api.ScavengersController do
  use NeuroScavWeb, :controller

  alias NeuroScav.{Locale, Scavengers, ScavengersServer}

  def generate_single(conn, _params) do
    locale = Locale.setup_locale(fetch_locale_from(conn))
    scavenger = ScavengersServer.generate_single(locale)
    render(conn, "single.json", scavenger: scavenger)
  end

  def generate_team(conn, _params) do
    locale = Locale.setup_locale(fetch_locale_from(conn))
    team = ScavengersServer.generate_team(locale)
    render(conn, "team.json", team: team)
  end

  def stats(conn, _params) do
    stats = Scavengers.get_statistics()
    render(conn, "stats.json", stats: stats)
  end

  defp fetch_locale_from(conn) do
    conn.params["lang"] || conn.cookies["lang"]
  end
end
