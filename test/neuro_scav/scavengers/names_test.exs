defmodule NeuroScav.ScavengersNamesTest do
  use ExUnit.Case, async: false

  alias NeuroScav.Scavengers.Names

  test "uniqueness first ru names" do
    actual = Enum.sort(Names.first_names_ru())
    assert Enum.sort(Enum.uniq(actual)) == actual
  end

  test "uniqueness last ru names" do
    actual = Enum.sort(Names.last_names_ru())
    assert Enum.sort(Enum.uniq(actual)) == actual
  end

  test "uniqueness first en names" do
    actual = Enum.sort(Names.first_names_en())
    assert Enum.sort(Enum.uniq(actual)) == actual
  end

  test "uniqueness last en names" do
    actual = Enum.sort(Names.last_names_en())
    assert Enum.sort(Enum.uniq(actual)) == actual
  end

  test "uniqueness legendary ru names" do
    actual = Enum.sort(Names.legendary_names_ru())
    assert Enum.sort(Enum.uniq(actual)) == actual
  end

  test "uniqueness legendary en names" do
    actual = Enum.sort(Names.legendary_names_en())
    assert Enum.sort(Enum.uniq(actual)) == actual
  end
end
