defmodule Mix.Tasks.Rarity.Sim do
  @shortdoc "Generates scavengers to check how their rarities come out"

  @moduledoc """
  Generates many scavengers the way the site does
  (`ScavengersServer.generate_scavenger/2`, the gnome included) without
  counting them anywhere, and prints how their rarities came out next to the
  exact chances (`ScavengersServer.odds/2`). A development tool: it runs from
  Mix, and Mix isn't part of a release, so it is never reachable from the site.

      mix rarity.sim                          # 100000 scavengers per locale
      mix rarity.sim --runs 1000000           # more scavengers, closer to the odds
      mix rarity.sim --locale en --seed 42    # one locale, the same ones every time
      mix rarity.sim --csv >> rarities.csv    # rows to collect over many runs

  For each rarity: how many came out, their share, the share expected and the
  deviation from it in standard deviations (σ). Within ±2σ is chance; past
  ±3σ (marked `!`) generation and the odds likely disagree.

  With `--csv` the output is comma-separated rows with the seed and the runs
  in each, so runs appended to one file can be told apart and summed up later.
  """

  use Mix.Task

  alias NeuroScav.Scavengers.Names
  alias NeuroScav.ScavengersServer

  @requirements ["compile"]

  @switches [runs: :integer, locale: :string, seed: :integer, csv: :boolean]
  @locales ~w(ru en de ja)
  @rarities [:gnome, :legendary, :epic, :rare, :uncommon, :common]

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    runs = Keyword.get(opts, :runs, 100_000)
    locales = locales(opts[:locale])
    # a seed of its own when none is given, printed so a run can be repeated
    seed = Keyword.get_lazy(opts, :seed, fn -> :rand.uniform(1_000_000) end)
    :rand.seed(:exsss, {seed, seed, seed})

    rows =
      for locale <- locales, row <- distribution(locale, runs), do: Map.put(row, :locale, locale)

    if opts[:csv], do: print_csv(rows, seed, runs), else: print_table(rows, seed, runs)
  end

  @doc """
  How `runs` scavengers of `locale` came out, a row per rarity: its `count`,
  `share` and `expected` share (percent), and the deviation in standard
  deviations (`sigma`, nil where the rarity can't come out).
  """
  @spec distribution(String.t(), pos_integer(), pos_integer() | nil) :: [map()]
  def distribution(locale, runs, gnome_odds \\ ScavengersServer.gnome_odds()) do
    names = ScavengersServer.names(Names, gnome_odds)
    counts = Enum.frequencies_by(1..runs, fn _ -> generate(names, locale) end)
    gnome = if gnome_odds, do: 1 / gnome_odds, else: 0.0

    # the gnome takes its share first, the rules split the rest
    chances =
      Names
      |> ScavengersServer.odds(locale)
      |> Map.new(fn {rarity, percent} -> {rarity, percent / 100 * (1 - gnome)} end)
      |> Map.put(:gnome, gnome)

    for rarity <- @rarities do
      count = Map.get(counts, rarity, 0)
      chance = Map.get(chances, rarity, 0.0)
      sd = :math.sqrt(runs * chance * (1 - chance))

      %{
        rarity: rarity,
        count: count,
        share: count * 100 / runs,
        expected: chance * 100,
        sigma: if(sd > 0, do: (count - runs * chance) / sd)
      }
    end
  end

  defp generate(names, locale), do: ScavengersServer.generate_scavenger(names, locale).rarity

  defp locales(nil), do: @locales
  defp locales(locale) when locale in @locales, do: [locale]

  defp locales(locale),
    do: Mix.raise("Unknown locale #{locale}, expected one of #{Enum.join(@locales, ", ")}")

  defp print_table(rows, seed, runs) do
    Mix.shell().info("Rarity distribution: #{runs} scavengers per locale, seed #{seed}")

    rows
    |> Enum.chunk_by(& &1.locale)
    |> Enum.each(fn [%{locale: locale} | _] = locale_rows ->
      Mix.shell().info(
        "\n" <>
          row([locale, "count", "share", "expected", "deviation"]) <>
          Enum.map_join(locale_rows, &("\n" <> table_row(&1)))
      )
    end)
  end

  defp table_row(row) do
    row([
      row.rarity,
      row.count,
      percent(row.share),
      percent(row.expected),
      deviation(row.sigma)
    ])
  end

  defp row([name | columns]) do
    String.pad_trailing(to_string(name), 10) <>
      Enum.map_join(columns, &String.pad_leading(to_string(&1), 11))
  end

  defp percent(value), do: :erlang.float_to_binary(value, decimals: 3) <> "%"

  defp deviation(nil), do: "—"

  defp deviation(sigma) do
    sign = if sigma >= 0, do: "+", else: ""
    mark = if abs(sigma) > 3, do: " !", else: ""
    sign <> :erlang.float_to_binary(sigma, decimals: 1) <> "σ" <> mark
  end

  defp print_csv(rows, seed, runs) do
    Mix.shell().info("seed,runs,locale,rarity,count,share,expected,sigma")

    for row <- rows do
      sigma = if row.sigma, do: :erlang.float_to_binary(row.sigma, decimals: 2), else: ""

      Mix.shell().info(
        Enum.join(
          [
            seed,
            runs,
            row.locale,
            row.rarity,
            row.count,
            :erlang.float_to_binary(row.share, decimals: 4),
            :erlang.float_to_binary(row.expected, decimals: 4),
            sigma
          ],
          ","
        )
      )
    end
  end
end
