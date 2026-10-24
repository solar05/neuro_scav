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

  ## Gnome

  Apart from the rules, any generated scavenger is the gnome (rarity `:gnome`,
  the name from the gnome footer) with a chance of 1 in `gnome_odds/0`. The
  `:gnome_odds` setting overrides it, `nil` turns the drop off (tests).

  ## Generated Scavengers

  Each scavenger is a map with:
  ```elixir
  %{
    name: "FirstName LastName",
    rarity: :common | :uncommon | :rare | :epic | :legendary | :gnome
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

  alias NeuroScav.{Locale, PubSub}

  @max_team_members 5
  @gnome_odds 2_000

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

  @doc """
  Generate a single scavenger for `user_id` synchronously (a battle card).

  Counts in statistics and announces legendaries like the other generations.
  """
  @spec generate_card(String.t(), String.t()) :: map()
  def generate_card(user_id, locale) do
    GenServer.call(__MODULE__, {:generate_card, user_id, locale})
  end

  @doc """
  Generate a scavenger without counting it in statistics or announcing it (bot players).
  """
  @spec generate_uncounted(String.t()) :: map()
  def generate_uncounted(locale) do
    GenServer.call(__MODULE__, {:generate_uncounted, locale})
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
  def generate_team(user_id, locale), do: generate_team(user_id, locale, @max_team_members)

  @doc """
  Like `generate_team/2`, but generates only `count` members — used to reroll
  the unlocked slots of a team.
  """
  @spec generate_team(String.t(), String.t(), pos_integer()) :: :ok
  def generate_team(user_id, locale, count) when count in 1..@max_team_members do
    GenServer.cast(__MODULE__, {:generate_team, user_id, locale, count})
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
  def init(%{module_name: names} = settings) do
    state = names(names, Map.get(settings, :gnome_odds, @gnome_odds))

    Logger.info("Scavenger server started")
    {:ok, state}
  end

  @spec load_names(module()) :: map()
  defp load_names(names) do
    %{
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
  end

  @impl true
  def handle_call({:generate_single, locale}, _from, state) do
    scavenger = generate_scavenger(state, locale)

    NeuroScav.StatsCounterServer.update_counter(scavenger.rarity)
    announce_legendaries([scavenger], nil)

    {:reply, scavenger, state}
  end

  @impl true
  def handle_call({:generate_uncounted, locale}, _from, state) do
    {:reply, generate_scavenger(state, locale), state}
  end

  @impl true
  def handle_call({:generate_card, user_id, locale}, _from, state) do
    scavenger = generate_scavenger(state, locale)

    NeuroScav.StatsCounterServer.update_counter(scavenger.rarity)
    announce_legendaries([scavenger], user_id)

    {:reply, scavenger, state}
  end

  @impl true
  def handle_call({:generate_team, locale}, _from, state) do
    team = 1..@max_team_members |> Enum.map(fn _ -> generate_scavenger(state, locale) end)

    team
    |> Enum.map(fn scav -> scav.rarity end)
    |> NeuroScav.StatsCounterServer.update_multiple_counters()

    announce_legendaries(team, nil)
    {:reply, team, state}
  end

  @impl true
  def handle_cast({:generate_single, user_id, locale}, state) do
    scavenger = generate_scavenger(state, locale)

    NeuroScav.StatsCounterServer.update_counter(scavenger.rarity)
    announce_legendaries([scavenger], user_id)
    PubSub.broadcast(user_id, {:single_generated, :single_scavenger, scavenger})

    {:noreply, state}
  end

  def handle_cast({:generate_team, user_id, locale, count}, state) do
    team = 1..count |> Enum.map(fn _ -> generate_scavenger(state, locale) end)

    team
    |> Enum.map(fn scav -> scav.rarity end)
    |> NeuroScav.StatsCounterServer.update_multiple_counters()

    announce_legendaries(team, user_id)
    PubSub.broadcast(user_id, {:team_generated, :team_scavengers, team})

    {:noreply, state}
  end

  defp announce_legendaries(scavengers, user_id) do
    for %{rarity: :legendary, name: name} <- scavengers, do: PubSub.broadcast_find(user_id, name)
    :ok
  end

  @doc false
  @spec max_team_members() :: integer()
  def max_team_members, do: @max_team_members

  @doc "A generated scavenger is the gnome with a chance of 1 in this."
  @spec gnome_odds() :: pos_integer()
  def gnome_odds, do: @gnome_odds

  @doc """
  What generation draws from, as the server keeps it: the name lists of the
  `module` and the gnome's odds (`nil`: no gnome). For `generate_scavenger/2`.
  """
  @spec names(module(), pos_integer() | nil) :: map()
  def names(module \\ NeuroScav.Scavengers.Names, gnome_odds \\ @gnome_odds),
    do: module |> load_names() |> Map.put(:gnome_odds, gnome_odds)

  @doc """
  A scavenger of `locale` generated as the server does, neither counted in
  statistics nor announced: the gnome with a chance of 1 in the odds,
  otherwise a random first and last name with its rarity. `names` comes from
  `names/2`. The site goes through the server; this is for tools
  (`mix rarity.sim`).
  """
  @spec generate_scavenger(map(), String.t()) :: map()
  def generate_scavenger(%{gnome_odds: odds} = names, locale) do
    if odds && :rand.uniform(odds) == 1,
      do: gnome(locale),
      else: name_pair(names, locale)
  end

  defp gnome(locale) do
    name =
      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn -> Locale.get_text("Gnome catched") end)

    %{name: name, rarity: :gnome}
  end

  defp name_pair(names, locale) do
    first_name =
      Map.get(names, "first_names_#{locale}") |> Enum.random()

    last_name =
      Map.get(names, "last_names_#{locale}") |> Enum.random()

    name = "#{first_name} #{last_name}"

    %{name: name, rarity: rarity(names, name, locale)}
  end

  @spec rarity(map(), String.t(), String.t()) :: atom()
  defp rarity(names, name, locale) do
    if legendary?(names, name, locale), do: :legendary, else: rule_rarity(name)
  end

  @spec rule_rarity(String.t()) :: atom()
  defp rule_rarity(name) do
    cond do
      epic?(name) -> :epic
      rare?(name) -> :rare
      uncommon?(name) -> :uncommon
      true -> :common
    end
  end

  @doc """
  Rarity of a name typed by a user, by the same rules as generation.

  Legendary names are matched case-insensitively against every locale's list
  and returned in their canonical spelling.
  """
  @spec check_name(String.t(), module()) :: map()
  def check_name(name, names \\ NeuroScav.Scavengers.Names) do
    state = load_names(names)
    downcased = String.downcase(name)

    legendary =
      ~w(ru en de ja)
      |> Enum.flat_map(&Map.fetch!(state, "legendary_names_#{&1}"))
      |> Enum.find(&(String.downcase(&1) == downcased))

    if legendary,
      do: %{name: legendary, rarity: :legendary},
      else: %{name: name, rarity: rule_rarity(name)}
  end

  @doc """
  Sets a team of names (two or more) collects, each one a battle bonus:

  - `:initial` - every first name starts with the same letter
  - `:rhyme` - at least two last names rhyme
  - `:length` - every last name has the same length
  """
  @spec team_sets([String.t()]) :: [atom()]
  def team_sets([_, _ | _] = names) do
    {firsts, lasts} = names |> Enum.map(&split_name/1) |> Enum.unzip()

    initials = Enum.map(firsts, &(&1 |> String.first() |> String.downcase()))
    rhymes = Enum.map(lasts, &rhyme_suffix/1)

    for {set, true} <- [
          initial: same?(initials),
          rhyme: Enum.uniq(rhymes) != rhymes,
          length: same?(Enum.map(lasts, &String.length/1))
        ],
        do: set
  end

  def team_sets(_names), do: []

  defp same?(values), do: values |> Enum.uniq() |> length() == 1

  @doc """
  Exact chance (in percent) of each rarity for `locale`.

  Walks every first × last name pair from the `names` module, so it takes
  seconds — call it once (e.g. at compile time), not per request.
  """
  @spec odds(module(), String.t()) :: %{atom() => float()}
  def odds(names, locale) do
    state = load_names(names)
    first_names = Map.fetch!(state, "first_names_#{locale}")
    last_names = Map.fetch!(state, "last_names_#{locale}")
    total = length(first_names) * length(last_names)

    counts =
      for first <- first_names, last <- last_names, reduce: %{} do
        acc -> Map.update(acc, rarity(state, "#{first} #{last}", locale), 1, &(&1 + 1))
      end

    Map.new(counts, fn {rarity, count} -> {rarity, count * 100 / total} end)
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
  3-character suffix ending at the last vowel and beyond.

  Examples: "Гена Лена" ("ена" == "ена"), "Маша Саша" ("аша" == "аша")

  ## Parameters

  - `name` - Full name to check ("FirstName LastName")

  ## Returns

  true if the rhyme suffix of first name == rhyme suffix of last name
  """
  @spec epic?(String.t()) :: boolean()
  def epic?(name) do
    {first, last} = split_name(name)
    rhyme_suffix(first) == rhyme_suffix(last)
  end

  @vowels ~w(a e i o u а е ё и о у ы э ю я)

  @spec rhyme_suffix(String.t()) :: String.t()
  defp rhyme_suffix(word) do
    graphemes = word |> String.downcase() |> String.graphemes()

    case Enum.reverse(graphemes) |> Enum.find_index(&(&1 in @vowels)) do
      nil ->
        Enum.join(graphemes)

      idx ->
        # Require at least 3 characters to avoid weak single-vowel matches
        # ("Дима"→"има", "Сотона"→"она" won't match; "Гена"→"ена", "Лена"→"ена" will).
        Enum.take(graphemes, -max(idx + 1, 3)) |> Enum.join()
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
    {first, last} = split_name(name)
    String.first(first) == String.first(last)
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
    {first, last} = split_name(name)
    String.length(first) == String.length(last)
  end

  @spec split_name(String.t()) :: {String.t(), String.t()}
  defp split_name(name) do
    parts = String.split(name, " ")
    {List.first(parts), List.last(parts)}
  end
end
