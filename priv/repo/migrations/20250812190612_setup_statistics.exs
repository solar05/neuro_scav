defmodule NeuroScav.Repo.Migrations.SetupStatistics do
  use Ecto.Migration

  alias NeuroScav.Scavengers

  def change do
    if Scavengers.get_statistics() == nil do
      Scavengers.create_statistics()
    end
  end
end
