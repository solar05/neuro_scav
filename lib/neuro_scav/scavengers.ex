defmodule NeuroScav.Scavengers do
  @moduledoc """
  The Scavengers context.
  """

  import Ecto.Query, warn: false
  alias NeuroScav.Repo

  alias NeuroScav.Scavengers.NeuroScavenger

  @doc """
  Returns the list of neuro_scavengers.

  ## Examples

      iex> list_neuro_scavengers()
      [%NeuroScavenger{}, ...]

  """
  def list_neuro_scavengers do
    Repo.all(NeuroScavenger)
  end

  @doc """
  Gets a single neuro_scavenger.

  Raises `Ecto.NoResultsError` if the Neuro scavenger does not exist.

  ## Examples

      iex> get_neuro_scavenger!(123)
      %NeuroScavenger{}

      iex> get_neuro_scavenger!(456)
      ** (Ecto.NoResultsError)

  """
  def get_neuro_scavenger!(id), do: Repo.get!(NeuroScavenger, id)

  @doc """
  Creates a neuro_scavenger.

  ## Examples

      iex> create_neuro_scavenger(%{field: value})
      {:ok, %NeuroScavenger{}}

      iex> create_neuro_scavenger(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_neuro_scavenger(attrs \\ %{}) do
    %NeuroScavenger{}
    |> NeuroScavenger.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a neuro_scavenger.

  ## Examples

      iex> update_neuro_scavenger(neuro_scavenger, %{field: new_value})
      {:ok, %NeuroScavenger{}}

      iex> update_neuro_scavenger(neuro_scavenger, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_neuro_scavenger(%NeuroScavenger{} = neuro_scavenger, attrs) do
    neuro_scavenger
    |> NeuroScavenger.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a neuro_scavenger.

  ## Examples

      iex> delete_neuro_scavenger(neuro_scavenger)
      {:ok, %NeuroScavenger{}}

      iex> delete_neuro_scavenger(neuro_scavenger)
      {:error, %Ecto.Changeset{}}

  """
  def delete_neuro_scavenger(%NeuroScavenger{} = neuro_scavenger) do
    Repo.delete(neuro_scavenger)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking neuro_scavenger changes.

  ## Examples

      iex> change_neuro_scavenger(neuro_scavenger)
      %Ecto.Changeset{data: %NeuroScavenger{}}

  """
  def change_neuro_scavenger(%NeuroScavenger{} = neuro_scavenger, attrs \\ %{}) do
    NeuroScavenger.changeset(neuro_scavenger, attrs)
  end
end
