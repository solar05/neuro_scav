defmodule NeuroScav.Repo.Migrations.CreateStatistics do
  use Ecto.Migration

  def change do
    create table(:statistics) do
      add :common, :bigint
      add :uncommon, :bigint
      add :rare, :bigint
      add :epic, :bigint
      add :legendary, :bigint
      add :neuro, :bigint
      add :gnome, :bigint
    end
  end
end
