defmodule NeuroScav.ScavengersNamesTest do
  use ExUnit.Case, async: false

  alias NeuroScav.Scavengers.Names

  test "uniqueness first ru names" do
    actual = Names.first_names_ru()
    assert actual == Enum.uniq(actual)
  end

  test "uniqueness last ru names" do
    actual = Names.last_names_ru()
    assert actual == Enum.uniq(actual)
  end

  test "uniqueness first en names" do
    actual = Names.first_names_en()
    assert actual == Enum.uniq(actual)
  end

  test "uniqueness last en names" do
    actual = Names.last_names_en()
    assert actual == Enum.uniq(actual)
  end

  test "uniqueness legendary ru names" do
    actual = Names.legendary_names_ru()
    assert actual == Enum.uniq(actual)
  end

  test "uniqueness legendary en names" do
    actual = Names.legendary_names_en()
    assert actual == Enum.uniq(actual)
  end
end
