defmodule NeuroScav.ScavengersFixtures do
  @moduledoc """
  Test helpers that create entities via the `NeuroScav.Scavengers` context.
  """

  def statistics_fixture(attrs \\ %{}) do
    {:ok, statistics} =
      attrs
      |> NeuroScav.Scavengers.create_statistics()

    statistics
  end
end
