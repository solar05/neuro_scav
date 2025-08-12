defmodule NeuroScav.Scavengers do
  @moduledoc """
  The Scavengers context.
  """

  import Ecto.Query, warn: false
  alias NeuroScav.Repo

  alias NeuroScav.Scavengers.Statistics

  def get_statistics!(id), do: Repo.get!(Statistics, id)

  def get_statistics(id), do: Repo.get(Statistics, id)

  def get_statistics() do
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

  def change_statistics(%Statistics{} = statistics, attrs \\ %{}) do
    Statistics.changeset(statistics, attrs)
  end
end
