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
      assert Server.generate_single("ru") == :ok
      assert GenServer.cast(Server, {:generate_single, "1234", "ru"})
      Process.sleep(1)
    end
  end

  describe "generate_team/1" do
    test "correctly generates team" do
      assert Server.generate_team("en") == :ok

      GenServer.cast(Server, {:generate_team, "1234", "en"})
      Process.sleep(1)
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
