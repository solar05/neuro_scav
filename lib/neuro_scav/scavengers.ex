defmodule NeuroScav.Scavengers do
  @moduledoc """
  The Scavengers context.
  """

  import Ecto.Query, warn: false
  alias NeuroScav.Repo

  alias NeuroScav.Scavengers.Statistics

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

  @doc """
  Adds `counts` (`%{counter => n}`) to a statistics row in one atomic update,
  so nothing counted before is lost whoever else counts at once, and returns
  the row as it is now; `{:error, reason}` when the database fails.
  """
  @spec increment_statistics(Statistics.t(), %{atom() => pos_integer()}) ::
          {:ok, Statistics.t()} | {:error, term()}
  def increment_statistics(%Statistics{id: id}, counts) do
    query = from(s in Statistics, where: s.id == ^id, select: s)

    case Repo.update_all(query, inc: Enum.to_list(counts)) do
      {1, [statistics]} -> {:ok, statistics}
      _none -> {:error, :not_found}
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end
end
