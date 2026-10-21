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

  # The generator builds "first last" from the pools, so a legendary whose parts
  # are missing from them can never drop.
  for locale <- ~w(ru en de ja) do
    test "every legendary #{locale} name can be generated" do
      locale = unquote(locale)
      first_names = apply(Names, :"first_names_#{locale}", [])
      last_names = apply(Names, :"last_names_#{locale}", [])

      unreachable =
        Enum.reject(apply(Names, :"legendary_names_#{locale}", []), fn name ->
          [first, last] = String.split(name, " ", parts: 2)
          first in first_names and last in last_names
        end)

      assert unreachable == []
    end
  end
end
