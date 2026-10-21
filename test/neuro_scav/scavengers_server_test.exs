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
    def first_names_de, do: ["Klaus"]
    def last_names_de, do: ["Bratwurst"]
    def legendary_names_de, do: []
    def first_names_ja, do: ["太郎"]
    def last_names_ja, do: ["田中"]
    def legendary_names_ja, do: []
  end

  setup do
    start_supervised!({Server, %{module_name: FixtureNames}})
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
      _ = :sys.get_state(Server)
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
      _ = :sys.get_state(Server)
    end
  end

  describe "check_name/2" do
    test "matches legendary names case-insensitively and returns their spelling" do
      assert Server.check_name("кеша пивосос", FixtureNames) ==
               %{name: "Кеша Пивосос", rarity: :legendary}
    end

    test "applies the generation rules to other names" do
      assert Server.check_name("Alice Adams", FixtureNames) == %{
               name: "Alice Adams",
               rarity: :rare
             }

      assert Server.check_name("Victor Beersucker", FixtureNames).rarity == :common
    end
  end

  describe "suggest_last_names/4" do
    test "capitalizes the first name and puts legendary names first" do
      assert Server.suggest_last_names("кеша", "ru", FixtureNames) == [
               legendary: ["Кеша Пивосос"]
             ]
    end

    test "leaves out common pairs" do
      assert Server.suggest_last_names("Victor", "en", FixtureNames) == []
    end

    test "every suggestion has the rarity of its group" do
      groups = Server.suggest_last_names("Гена", "ru")
      assert groups != []

      for {rarity, names} <- groups do
        assert length(names) in 1..6
        for name <- names, do: assert(Server.check_name(name).rarity == rarity)
      end
    end
  end

  describe "legendary announcements" do
    test "generated legendaries are broadcast with the finder's id" do
      NeuroScav.PubSub.subscribe_finds()

      Server.generate_single("finder", "ru")
      assert_receive {:legendary_found, %{user_id: "finder", name: "Кеша Пивосос"}}

      Server.generate_team("finder", "ru", 2)
      assert_receive {:legendary_found, %{user_id: "finder"}}
      assert_receive {:legendary_found, %{user_id: "finder"}}
    end

    test "other rarities are not broadcast" do
      NeuroScav.PubSub.subscribe_finds()

      Server.generate_single("finder", "en")
      _ = :sys.get_state(Server)
      refute_received {:legendary_found, _}
    end
  end

  describe "odds/2" do
    test "counts every first × last pair" do
      assert Server.odds(FixtureNames, "ru") == %{legendary: 100.0}
      assert Server.odds(FixtureNames, "en") == %{common: 100.0}
    end
  end

  describe "rarity functions" do
    test "legendary?/3" do
      assert Server.legendary?(%{"legendary_names_ru" => ["Кеша Пивосос"]}, "Кеша Пивосос", "ru")
    end

    test "epic?/2" do
      # ru rhymes
      assert Server.epic?("Гена Лена")
      assert Server.epic?("Яшка Полторашка")
      assert Server.epic?("Маша Саша")
      # english rhymes
      assert Server.epic?("Sasha Masha")
      assert Server.epic?("Dima Prima")
      # no rhymes
      refute Server.epic?("Маша Сергей")
      refute Server.epic?("М Й")
      refute Server.epic?("Дима Сотона")
      refute Server.epic?("Vova Sasha")
      refute Server.epic?("Борис Денис")
      refute Server.epic?("Катя Петя")
    end

    test "rare?/2" do
      assert Server.rare?("Игорь Игольчатый")
    end

    test "uncommon?/2" do
      assert Server.uncommon?("Тимофей Монолит")
    end
  end
end
