defmodule NeuroScavWeb.Api.ScavengersController do
  use NeuroScavWeb, :controller

  alias NeuroScav.{BattleRoom, Locale, Scavengers, ScavengersServer}

  # same limit as the name check page
  @max_name_length 40

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

  # rarity and battle card of any name; rarity rules compare first and last words
  def check_name(conn, %{"name" => name}) when is_binary(name) do
    name = name |> String.split() |> Enum.join(" ") |> String.slice(0, @max_name_length)

    case String.split(name) do
      [_first, _last | _] ->
        render(conn, "card.json", card: ScavengersServer.check_name(name) |> BattleRoom.card())

      _ ->
        name_required(conn)
    end
  end

  def check_name(conn, _params), do: name_required(conn)

  defp name_required(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "name must have a first and a last name"})
  end

  defp fetch_locale_from(conn) do
    conn.params["lang"] || conn.cookies["lang"]
  end
end
