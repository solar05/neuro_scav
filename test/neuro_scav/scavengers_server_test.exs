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
    start_supervised!({Server, %{module_name: FixtureNames, gnome_odds: nil}})
    :ok
  end

  describe "gnome drop" do
    setup do
      stop_supervised!(Server)
      start_supervised!({Server, %{module_name: FixtureNames, gnome_odds: 1}})
      :ok
    end

    test "replaces a generated scavenger with the gnome, named in the locale" do
      assert Server.generate_single("ru") == %{name: "ГНОМ ГНОМЫЧ", rarity: :gnome}

      assert Enum.all?(
               Server.generate_team("en"),
               &(&1 == %{name: "Gnome Gnomich", rarity: :gnome})
             )
    end
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

  describe "team_sets/1" do
    test "finds the sets a team collects" do
      assert Server.team_sets(["Анна Кот", "Алла Лисица", "Ася Смирнова"]) == [:initial]
      assert Server.team_sets(["Гена Лебедев", "Дима Ворона", "Олег Борона"]) == [:rhyme]
      assert Server.team_sets(["Гена Кот", "Дима Лис", "Олег Сом"]) == [:length]

      assert Server.team_sets(["Ира Лебеда", "Ира Ворона", "Ира Борона"]) == [
               :initial,
               :rhyme,
               :length
             ]
    end

    test "a lone card or an unmatched team collects nothing" do
      assert Server.team_sets(["Анна Анна"]) == []
      assert Server.team_sets(["Анна Иванова", "Борис Кот", "Вера Лисица"]) == []
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

    test "uncounted generations (bot cards) are not broadcast" do
      NeuroScav.PubSub.subscribe_finds()

      assert %{name: "Кеша Пивосос", rarity: :legendary} = Server.generate_uncounted("ru")
      refute_received {:legendary_found, _}
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
