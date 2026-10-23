defmodule NeuroScavWeb.Api.ScavengersJSON do
  def render("team.json", %{team: team}) do
    %{team: render_many(team)}
  end

  def render("single.json", %{scavenger: scavenger}) do
    %{scavenger: render_one(scavenger)}
  end

  def render("stats.json", %{stats: stats}) do
    %{
      legendary: Map.get(stats, :legendary, 0),
      epic: Map.get(stats, :epic, 0),
      rare: Map.get(stats, :rare, 0),
      uncommon: Map.get(stats, :uncommon, 0),
      common: Map.get(stats, :common, 0),
      neuro: Map.get(stats, :neuro, 0),
      gnome: Map.get(stats, :gnome, 0)
    }
  end

  def render_one(scavenger) do
    %{
      name: Map.get(scavenger, :name),
      rarity: Map.get(scavenger, :rarity)
    }
  end

  def render_many(team) do
    Enum.map(team, fn scavenger ->
      render_one(scavenger)
    end)
  end
end
