defmodule NeuroScav.Scavengers.RaidStatistics do
  @moduledoc """
  How raids (`NeuroScav.Raid`) went at a location, a row per location: the
  raids finished, those nobody came out of, the scavs sent and those that
  came out. Rows are only ever incremented (`NeuroScav.Scavengers.record_raid/1`).
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "raid_statistics" do
    field :location, :string
    field :raids, :integer, default: 0
    field :wiped, :integer, default: 0
    field :members, :integer, default: 0
    field :survivors, :integer, default: 0
  end
end
