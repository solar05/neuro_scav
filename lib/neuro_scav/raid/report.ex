defmodule NeuroScav.Raid.Report do
  @moduledoc """
  A finished raid in short, to share: where it was (`location`), the exit
  the squad got out through (`exit`, nil when nobody did), the squad
  (`members`: name, rarity, whether they made it), the loot carried out
  (`loot`: what alive finders hold) and the language it's told in (`lang`).

  It travels in a link as a token (`encode/1`, `decode/1`): JSON in URL-safe
  Base64. A token comes from anyone, so `decode/1` checks every part against
  what raids are made of and turns names into known atoms only.
  """

  alias NeuroScav.Raid
  alias NeuroScav.Raid.Catalog

  @version 1
  @langs ~w(ru en de ja)
  @max_members NeuroScav.ScavengersServer.max_team_members()
  @max_name 40
  @max_loot 40
  @max_token 4000

  # what a token may name, by its string
  @locations Map.new(Raid.locations(), &{Atom.to_string(&1), &1})
  @exits Map.new(Catalog.compiled().exits, &{Atom.to_string(&1), &1})
  @loot Map.new(Raid.loot(), &{Atom.to_string(&1), &1})
  @rarities Map.new(~w(common uncommon rare epic legendary gnome)a, &{Atom.to_string(&1), &1})

  @type t :: %{
          location: atom() | nil,
          exit: atom() | nil,
          members: [%{name: String.t(), rarity: atom(), alive: boolean()}],
          loot: [atom()],
          lang: String.t()
        }

  @doc "The report of a finished `raid`, told in `lang` (Russian unless one of the site's)."
  @spec new(map(), String.t() | nil) :: t()
  def new(raid, lang) do
    at = Raid.at(raid)
    event = at && raid.map.nodes[at]

    %{
      location: Raid.location(raid),
      exit: if(event && Raid.exit?(event) && Raid.alive(raid) != [], do: event),
      members: for(m <- raid.squad, do: %{name: m.name, rarity: m.rarity, alive: m.alive}),
      loot: for(entry <- raid.stash, Raid.active?(raid, entry), do: entry.item),
      lang: if(lang in @langs, do: lang, else: "ru")
    }
  end

  @doc "The report as a token for a link."
  @spec encode(t()) :: String.t()
  def encode(report) do
    %{
      "v" => @version,
      "l" => report.location,
      "e" => report.exit,
      "m" => Enum.map(report.members, &[&1.name, &1.rarity, if(&1.alive, do: 1, else: 0)]),
      "i" => report.loot,
      "g" => report.lang
    }
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @doc "The report a token holds, `:error` for anything that isn't one."
  @spec decode(term()) :: {:ok, t()} | :error
  def decode(token) when is_binary(token) and byte_size(token) <= @max_token do
    with {:ok, json} <- Base.url_decode64(token, padding: false),
         {:ok, %{"v" => @version, "m" => members, "i" => items} = data} <- Jason.decode(json),
         {:ok, members} <- members(members),
         {:ok, loot} <- known_all(items, @loot),
         {:ok, location} <- known(data["l"], @locations),
         {:ok, exit} <- known(data["e"], @exits) do
      lang = if data["g"] in @langs, do: data["g"], else: "ru"
      {:ok, %{location: location, exit: exit, members: members, loot: loot, lang: lang}}
    else
      _invalid -> :error
    end
  end

  def decode(_token), do: :error

  defp members(list) when is_list(list) and length(list) in 1..@max_members do
    list
    |> Enum.map(fn
      [name, rarity, alive] when is_binary(name) and alive in [0, 1] ->
        with true <- String.valid?(name) and String.length(name) in 1..@max_name,
             {:ok, rarity} <- known_name(rarity, @rarities) do
          {:ok, %{name: name, rarity: rarity, alive: alive == 1}}
        end

      _invalid ->
        :error
    end)
    |> all_ok()
  end

  defp members(_list), do: :error

  defp known_all(list, names) when is_list(list) and length(list) <= @max_loot,
    do: list |> Enum.map(&known_name(&1, names)) |> all_ok()

  defp known_all(_list, _names), do: :error

  # a name the token may leave out (nil), or one it must give
  defp known(nil, _names), do: {:ok, nil}
  defp known(name, names), do: known_name(name, names)

  defp known_name(name, names) when is_binary(name), do: Map.fetch(names, name)
  defp known_name(_name, _names), do: :error

  defp all_ok(results) do
    if Enum.all?(results, &match?({:ok, _value}, &1)),
      do: {:ok, Enum.map(results, &elem(&1, 1))},
      else: :error
  end
end
