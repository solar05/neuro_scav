defmodule NeuroScav.Scavengers.Statistics do
  @moduledoc """
  Neuro scavenger schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "statistics" do
    field :common, :integer, default: 0
    field :uncommon, :integer, default: 0
    field :rare, :integer, default: 0
    field :epic, :integer, default: 0
    field :legendary, :integer, default: 0
    field :neuro, :integer, default: 0
    field :gnome, :integer, default: 0
  end

  @doc false
  def changeset(statistics, attrs) do
    statistics
    |> cast(attrs, [:common, :uncommon, :rare, :epic, :legendary, :neuro, :gnome])
    |> validate_required([:common, :uncommon, :rare, :epic, :legendary, :neuro, :gnome])
  end
end
