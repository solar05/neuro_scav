defmodule NeuroScav.ScavengersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `NeuroScav.Scavengers` context.
  """

  @doc """
  Generate a neuro_scavenger.
  """
  def neuro_scavenger_fixture(attrs \\ %{}) do
    {:ok, neuro_scavenger} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> NeuroScav.Scavengers.create_neuro_scavenger()

    neuro_scavenger
  end
end
