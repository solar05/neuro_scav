defmodule NeuroScav.Repo.Migrations.DropRaidStatistics do
  use Ecto.Migration

  # raids aren't counted any more; down brings the table back empty
  def up do
    drop table(:raid_statistics)
  end

  def down do
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
