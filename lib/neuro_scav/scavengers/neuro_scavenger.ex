defmodule NeuroScav.Scavengers.NeuroScavenger do
  @moduledoc """
  Neuro scavenger schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "neuro_scavengers" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(neuro_scavenger, attrs) do
    neuro_scavenger
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
