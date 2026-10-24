defmodule NeuroScav.Repo.Migrations.CreateRaidStatistics do
  use Ecto.Migration

  def change do
    create table(:raid_statistics) do
      add :location, :string, null: false
      add :raids, :bigint, null: false, default: 0
      add :wiped, :bigint, null: false, default: 0
      add :members, :bigint, null: false, default: 0
      add :survivors, :bigint, null: false, default: 0
    end

    create unique_index(:raid_statistics, [:location])
  end
end
