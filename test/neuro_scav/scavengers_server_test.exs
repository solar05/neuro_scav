defmodule NeuroScav.ScavengersServerTest do
  alias NeuroScav.ScavengersServer, as: Server

  use ExUnit.Case, async: false

  defmodule FixtureNames do
    def first_names_ru, do: ["Кеша"]
    def last_names_ru, do: ["Пивосос"]
    def legendary_names_ru, do: ["Кеша Пивосос"]
    def first_names_en, do: ["Victor"]
    def last_names_en, do: ["Beersucker"]
    def legendary_names_en, do: []
  end

  setup do
    default_settings = %{module_name: FixtureNames}
    GenServer.start_link(Server, default_settings, name: Server)
    :ok
  end

  describe "generate_single/1" do
    test "correctly generates scavenger" do
      result = Server.generate_single("ru")
      assert is_map(result)
      assert result.name == "Кеша Пивосос"
      assert result.rarity == :legendary
    end

    test "adjust test coverage" do
      assert Server.generate_single("some-id", "en") == :ok
      Process.sleep(100)
    end
  end

  describe "test max_members" do
    test "adjust test coverage" do
      assert is_integer(Server.max_team_members())
    end
  end

  describe "generate_team/1" do
    test "correctly generates team" do
      result = Server.generate_team("en")
      assert length(result) == 5
    end

    test "adjust test coverage" do
      assert Server.generate_team("some-id", "en") == :ok
      Process.sleep(100)
    end
  end

  describe "rarity functions" do
    test "legendary?/3" do
      assert Server.legendary?(%{"legendary_names_ru" => ["Кеша Пивосос"]}, "Кеша Пивосос", "ru")
    end

    test "epic?/2" do
      assert Server.epic?("Яшка Полторашка")
    end

    test "rare?/2" do
      assert Server.rare?("Игорь Игольчатый")
    end

    test "uncommon?/2" do
      assert Server.uncommon?("Тимофей Монолит")
    end
  end
end
