defmodule NeuroScav.Repo.Migrations.CreateNeuroScavengers do
  use Ecto.Migration

  def change do
    create table(:neuro_scavengers) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end
