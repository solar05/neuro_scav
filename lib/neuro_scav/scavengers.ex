defmodule NeuroScav.Scavengers do
  @moduledoc """
  The Scavengers context.
  """

  import Ecto.Query, warn: false
  alias NeuroScav.{PubSub, Repo}

  alias NeuroScav.Scavengers.{RaidStatistics, Statistics}

  def get_statistics!(id), do: Repo.get!(Statistics, id)

  def get_statistics(id), do: Repo.get(Statistics, id)

  def get_statistics do
    from(Statistics, order_by: [:id], limit: 1)
    |> Repo.one()
  end

  def create_statistics(attrs \\ %{}) do
    %Statistics{}
    |> Statistics.changeset(attrs)
    |> Repo.insert()
  end

  def update_statistics(%Statistics{} = statistics, attrs) do
    statistics
    |> Statistics.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Counts a finished raid (a `NeuroScav.Raid.Report`) in its location's row —
  an atomic increment, so raids ending at once all count — and tells the
  statistics page. A raid of no location (a fixed route) isn't counted.
  """
  @spec record_raid(map()) :: :ok | {:error, term()}
  def record_raid(%{location: nil}), do: :ok

  def record_raid(%{location: location, members: members}) do
    survivors = Enum.count(members, & &1.alive)

    counts = [
      raids: 1,
      wiped: if(survivors == 0, do: 1, else: 0),
      members: length(members),
      survivors: survivors
    ]

    Repo.insert_all(RaidStatistics, [[{:location, to_string(location)} | counts]],
      on_conflict: [inc: counts],
      conflict_target: :location
    )

    PubSub.broadcast_raid_statistics(list_raid_statistics())
  end

  @doc "Every location's raid statistics, the most raided first."
  @spec list_raid_statistics() :: [RaidStatistics.t()]
  def list_raid_statistics,
    do: Repo.all(from(s in RaidStatistics, order_by: [desc: s.raids, asc: s.location]))
end
