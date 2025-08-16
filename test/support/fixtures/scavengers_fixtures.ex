defmodule NeuroScav.ScavengersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `NeuroScav.Scavengers` context.
  """

  def statistics_fixture(attrs \\ %{}) do
    {:ok, statistics} =
      attrs
      |> NeuroScav.Scavengers.create_statistics()

    statistics
  end
end
