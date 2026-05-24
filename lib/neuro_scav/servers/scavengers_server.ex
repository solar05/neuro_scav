defmodule NeuroScav.ScavengersServer do
  @moduledoc """
  Scavenger generation and rarity calculation engine.

  This GenServer manages the generation of scavenger names with calculated rarity levels.
  It uses deterministic algorithms to assign rarity based on name properties.

  ## Rarity Algorithm

  Rarities are calculated based on first and last name properties:

  1. **Legendary** - Name matches a predefined legendary name list for the language
  2. **Epic** - First and last names rhyme — share the same suffix from the last vowel (e.g., "Гена Лена", "Борис Денис")
  3. **Rare** - First and last names start with the same character (e.g., "Alice Abrams")
  4. **Uncommon** - First and last names have equal length (e.g., "Tom Ward")
  5. **Common** - Default for names matching no criteria

  This algorithm is deterministic - the same name always generates the same rarity.

  ## Generated Scavengers

  Each scavenger is a map with:
  ```elixir
  %{
    name: "FirstName LastName",
    rarity: :common | :uncommon | :rare | :epic | :legendary
  }
  ```

  ## Generation Modes

  - **Single**: Generate one scavenger
  - **Team**: Generate exactly 5 scavengers for a team

  ## State Management

  The server maintains language-specific name lists in its state:
  - First names (English & Russian)
  - Last names (English & Russian)
  - Legendary names (English & Russian)

  Names are randomly selected from these lists for each generation.

  ## Asynchronous vs Synchronous

  - `generate_single/1`, `generate_team/1` - Synchronous (GenServer.call)
  - `generate_single/2`, `generate_team/2` - Asynchronous (GenServer.cast)

  Asynchronous versions notify the user via PubSub after generation.
  """

  require Logger

  use GenServer

  alias NeuroScav.PubSub

  @max_team_members 5

  # Public API - Synchronous

  @doc """
  Generate a single scavenger synchronously (blocking call).

  Returns immediately with the generated scavenger map.

  ## Parameters

  - `locale` - Language code ("en" or "ru")

  ## Returns

  Map with keys:
  - `:name` - Generated scavenger name
  - `:rarity` - Calculated rarity level

  ## Example

      iex> ScavengersServer.generate_single("en")
      %{name: "John Smith", rarity: :common}
  """
  @spec generate_single(String.t()) :: map()
  def generate_single(locale) do
    GenServer.call(__MODULE__, {:generate_single, locale})
  end

  @doc """
  Generate a team of 5 scavengers synchronously (blocking call).

  Returns immediately with a list of 5 scavenger maps.

  ## Parameters

  - `locale` - Language code ("en" or "ru")

  ## Returns

  List of 5 scavenger maps with `:name` and `:rarity` keys

  ## Example

      iex> ScavengersServer.generate_team("en")
      [
        %{name: "Alice Anderson", rarity: :rare},
        %{name: "Bob Brown", rarity: :common},
        ...
      ]
  """
  @spec generate_team(String.t()) :: list(map())
  def generate_team(locale) do
    GenServer.call(__MODULE__, {:generate_team, locale})
  end

  # Public API - Asynchronous

  @doc """
  Generate a single scavenger asynchronously for a user.

  Queues the generation and broadcasts result via PubSub to the user.
  Does not block the caller.

  ## Parameters

  - `user_id` - User identifier
  - `locale` - Language code ("en" or "ru")

  ## Returns

  `:ok`

  ## Side Effects

  Broadcasts `{:single_generated, :single_scavenger, scavenger}` to user's topic
  """
  @spec generate_single(String.t(), String.t()) :: :ok
  def generate_single(user_id, locale) do
    GenServer.cast(__MODULE__, {:generate_single, user_id, locale})
  end

  @doc """
  Generate a team of 5 scavengers asynchronously for a user.

  Queues the generation and broadcasts result via PubSub to the user.
  Does not block the caller.

  ## Parameters

  - `user_id` - User identifier
  - `locale` - Language code ("en" or "ru")

  ## Returns

  `:ok`

  ## Side Effects

  Broadcasts `{:team_generated, :team_scavengers, team}` to user's topic
  Updates statistics counters with team rarities
  """
  @spec generate_team(String.t(), String.t()) :: :ok
  def generate_team(user_id, locale) do
    GenServer.cast(__MODULE__, {:generate_team, user_id, locale})
  end

  # GenServer Callbacks

  @doc false
  def start_link(settings) do
    GenServer.start_link(
      __MODULE__,
      settings,
      name: __MODULE__
    )
  end

  @impl true
  def init(%{module_name: names} = _default_state) do
    state = %{
      "first_names_ru" => names.first_names_ru(),
      "last_names_ru" => names.last_names_ru(),
      "first_names_en" => names.first_names_en(),
      "last_names_en" => names.last_names_en(),
      "legendary_names_ru" => names.legendary_names_ru(),
      "legendary_names_en" => names.legendary_names_en(),
      "first_names_ja" => names.first_names_ja(),
      "last_names_ja" => names.last_names_ja(),
      "legendary_names_ja" => names.legendary_names_ja(),
      "first_names_de" => names.first_names_de(),
      "last_names_de" => names.last_names_de(),
      "legendary_names_de" => names.legendary_names_de()
    }

    Logger.info("Scavenger server started")
    {:ok, state}
  end

  @impl true
  def handle_call({:generate_single, locale}, _from, state) do
    scavenger = generate_scavenger(state, locale)

    NeuroScav.StatsCounterServer.update_counter(scavenger.rarity)

    {:reply, scavenger, state}
  end

  @impl true
  def handle_call({:generate_team, locale}, _from, state) do
    team = 1..@max_team_members |> Enum.map(fn _ -> generate_scavenger(state, locale) end)

    team
    |> Enum.map(fn scav -> scav.rarity end)
    |> NeuroScav.StatsCounterServer.update_multiple_counters()

    {:reply, team, state}
  end

  @impl true
  def handle_cast({:generate_single, user_id, locale}, state) do
    scavenger = generate_scavenger(state, locale)

    NeuroScav.StatsCounterServer.update_counter(scavenger.rarity)
    PubSub.broadcast(user_id, {:single_generated, :single_scavenger, scavenger})

    {:noreply, state}
  end

  def handle_cast({:generate_team, user_id, locale}, state) do
    team = 1..@max_team_members |> Enum.map(fn _ -> generate_scavenger(state, locale) end)

    team
    |> Enum.map(fn scav -> scav.rarity end)
    |> NeuroScav.StatsCounterServer.update_multiple_counters()

    PubSub.broadcast(user_id, {:team_generated, :team_scavengers, team})

    {:noreply, state}
  end

  @doc false
  @spec max_team_members() :: integer()
  def max_team_members, do: @max_team_members

  @doc false
  @spec generate_scavenger(map(), String.t()) :: map()
  defp generate_scavenger(names, locale) do
    first_name =
      Map.get(names, "first_names_#{locale}") |> Enum.random()

    last_name =
      Map.get(names, "last_names_#{locale}") |> Enum.random()

    name = "#{first_name} #{last_name}"

    rarity =
      cond do
        legendary?(names, name, locale) == true -> :legendary
        epic?(name) == true -> :epic
        rare?(name) == true -> :rare
        uncommon?(name) == true -> :uncommon
        true -> :common
      end

    %{name: name, rarity: rarity}
  end

  @doc """
  Check if a name matches the legendary names list for the language.

  Legendary names are special predefined names that are guaranteed to be rare.

  ## Parameters

  - `names` - State map containing legendary_names_* lists
  - `name` - Full name to check ("FirstName LastName")
  - `locale` - Language code ("en" or "ru")

  ## Returns

  true if name is in the legendary list, false otherwise
  """
  @spec legendary?(map(), String.t(), String.t()) :: boolean()
  def legendary?(names, name, locale) do
    Map.get(names, "legendary_names_#{locale}") |> Enum.member?(name)
  end

  @doc """
  Check if a name is epic rarity.

  A name is epic if the first and last names rhyme — they share the same
  suffix starting from the last vowel (the "rime" of the final syllable).

  Examples: "Гена Лена" ("-а" == "-а"), "Борис Денис" ("-ис" == "-ис")

  ## Parameters

  - `name` - Full name to check ("FirstName LastName")

  ## Returns

  true if the rhyme suffix of first name == rhyme suffix of last name
  """
  @spec epic?(String.t()) :: boolean()
  def epic?(name) do
    splitted_name = String.split(name, " ")
    first_name = List.first(splitted_name)
    last_name = List.last(splitted_name)
    rhyme_suffix(first_name) == rhyme_suffix(last_name)
  end

  @vowels ~w(a e i o u а е ё и о у ы э ю я)

  @spec rhyme_suffix(String.t()) :: String.t()
  defp rhyme_suffix(word) do
    graphemes = word |> String.downcase() |> String.graphemes()

    case Enum.reverse(graphemes) |> Enum.find_index(&(&1 in @vowels)) do
      nil -> Enum.join(graphemes)
      idx ->
        graphemes
        |> Enum.drop(length(graphemes) - idx - 1)
        |> Enum.join()
    end
  end

  @doc """
  Check if a name is rare rarity.

  A name is rare if the first and last names start with the same character.

  Examples: "Alice Abrams", "David Denver"

  ## Parameters

  - `name` - Full name to check ("FirstName LastName")

  ## Returns

  true if first char of first name == first char of last name
  """
  @spec rare?(String.t()) :: boolean()
  def rare?(name) do
    splitted_name = String.split(name, " ")
    first_name = List.first(splitted_name)
    last_name = List.last(splitted_name)
    String.first(first_name) == String.first(last_name)
  end

  @doc """
  Check if a name is uncommon rarity.

  A name is uncommon if the first and last names have the same character length.

  Examples: "Tom Ward", "Alice Smith"

  ## Parameters

  - `name` - Full name to check ("FirstName LastName")

  ## Returns

  true if length of first name == length of last name
  """
  @spec uncommon?(String.t()) :: boolean()
  def uncommon?(name) do
    splitted_name = String.split(name, " ")
    first_name = List.first(splitted_name)
    last_name = List.last(splitted_name)
    String.length(first_name) == String.length(last_name)
  end
end
