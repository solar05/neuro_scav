defmodule Mix.Tasks.Raid.Sim do
  @shortdoc "Simulates raids to tune their balance (development only)"

  @moduledoc """
  Plays many raids (`NeuroScav.Raid`) with random squads and prints how they
  end. A development tool for trying new raid mechanics: it runs from Mix, and
  Mix isn't part of a release, so it is never reachable from the site.

      mix raid.sim                              # 5000 raids per strategy
      mix raid.sim --runs 20000 --seed 42       # more raids, the same ones every time
      mix raid.sim --strategy greedy --events   # one strategy, with a table per event
      mix raid.sim --route pmc,veteran,labs     # a fixed route instead of a random one
      mix raid.sim --locale en                  # squads from English names

  At every event a strategy picks an option:

  - `cautious` - the safe option when there is one, otherwise the best chance
  - `greedy` - the best chance, never the safe option
  - `random` - any option

  Squads are five random first and last names of the locale, rarity by the
  usual rules (`ScavengersServer.check_name/1`).
  """

  use Mix.Task

  alias NeuroScav.{Raid, ScavengersServer}
  alias NeuroScav.Scavengers.Names

  @requirements ["compile"]

  @strategies ~w(cautious greedy random)
  @switches [
    runs: :integer,
    strategy: :string,
    locale: :string,
    seed: :integer,
    route: :string,
    events: :boolean
  ]
  # outcomes a raid may or may not meet, shown as the share of raids with one
  @outcomes [:loot, :train, :wound, :promote, :trophy, :revive, :drop]
  @successes [:pass, :loot, :revive, :train, :promote, :trophy]
  @squad_size 5

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    runs = Keyword.get(opts, :runs, 5_000)
    locale = Keyword.get(opts, :locale, "ru")
    # a seed of its own when none is given, printed so a run can be repeated
    seed = Keyword.get_lazy(opts, :seed, fn -> :rand.uniform(1_000_000) end)
    :rand.seed(:exsss, {seed, seed, seed})

    strategies = strategies(opts[:strategy])
    route = route(opts[:route])
    names = names(locale)

    Mix.shell().info(
      "#{runs} raids per strategy, locale #{locale}, seed #{seed}, " <>
        if(route, do: "route #{Enum.join(route, ",")}", else: "random routes")
    )

    results = Map.new(strategies, &{&1, simulate(&1, runs, names, route)})

    print_summary(strategies, results)
    if opts[:events], do: Enum.each(strategies, &print_events(&1, results[&1]))
  end

  @doc """
  Plays `runs` raids with `strategy`; each result is the finished raid and
  what happened at every event, in order. `names` is `{first_names,
  last_names}`, `route` a fixed route or nil for a random one each time.
  """
  @spec simulate(String.t(), pos_integer(), {[String.t()], [String.t()]}, [atom()] | nil) ::
          [{map(), [map()]}]
  def simulate(strategy, runs, {firsts, lasts}, route \\ nil) do
    for _ <- 1..runs do
      squad =
        for _ <- 1..@squad_size,
            do: ScavengersServer.check_name("#{Enum.random(firsts)} #{Enum.random(lasts)}")

      play(Raid.new(squad, route || Raid.route()), strategy, [])
    end
  end

  defp play(raid, strategy, log) do
    if Raid.over?(raid) do
      {raid, Enum.reverse(log)}
    else
      raid = Raid.choose(raid, pick(strategy, Raid.options(raid)), :rand.uniform(100))
      play(raid, strategy, [raid.last | log])
    end
  end

  defp pick("cautious", options), do: Enum.find_index(options, &is_nil(&1.stat)) || best(options)
  defp pick("greedy", options), do: best(options)
  defp pick("random", options), do: Enum.random(0..(length(options) - 1))

  # a crossroads has no check: its first path then
  defp best(options) do
    options
    |> Enum.with_index()
    |> Enum.reject(fn {option, _index} -> is_nil(option.stat) end)
    |> Enum.max_by(fn {option, _index} -> option.chance end, fn -> {nil, 0} end)
    |> elem(1)
  end

  @doc "How raids ended: shares in percent, averages per raid."
  @spec summary([{map(), [map()]}]) :: map()
  def summary(results) do
    alive = Enum.map(results, fn {raid, _log} -> length(Raid.alive(raid)) end)

    %{
      wiped: share(alive, &(&1 == 0)),
      clean:
        share(results, fn {raid, _log} -> length(Raid.alive(raid)) == length(raid.squad) end),
      alive: average(alive),
      steps: average(Enum.map(results, fn {_raid, log} -> length(log) end)),
      stash: average(Enum.map(results, fn {raid, _log} -> length(raid.stash) end)),
      karma: average(Enum.map(results, fn {raid, _log} -> raid.karma end)),
      with:
        Map.new(@outcomes, fn outcome ->
          {outcome,
           share(results, fn {_raid, log} -> Enum.any?(log, &(&1.outcome == outcome)) end)}
        end)
    }
  end

  @doc """
  Per event: how many raids met it, and how its plays went (success, death,
  the safe option), in percent.
  """
  @spec events([{map(), [map()]}]) :: [{atom(), map()}]
  def events(results) do
    for {event, plays} <-
          Enum.group_by(for({_raid, log} <- results, play <- log, do: play), & &1.event),
        into: [] do
      {event,
       %{
         met: length(plays) * 100 / length(results),
         success: share(plays, &(&1.outcome in @successes)),
         died: share(plays, &(&1.outcome == :lose)),
         safe: share(plays, &(&1.outcome == :safe))
       }}
    end
    |> Enum.sort()
  end

  defp print_summary(strategies, results) do
    outcomes = Enum.map(@outcomes, &Atom.to_string/1)
    header = ~w(strategy wiped clean alive steps stash karma) ++ outcomes
    rows = for strategy <- strategies, do: [strategy | summary_row(summary(results[strategy]))]

    Mix.shell().info("\nRaids (outcome columns: share of raids that met one)")
    print_table(header, rows)
  end

  defp summary_row(summary) do
    [percent(summary.wiped), percent(summary.clean), number(summary.alive)] ++
      [number(summary.steps), number(summary.stash), number(summary.karma)] ++
      Enum.map(@outcomes, &percent(summary.with[&1]))
  end

  defp print_events(strategy, results) do
    rows =
      for {event, stats} <- events(results),
          do: [event | Enum.map([stats.met, stats.success, stats.died, stats.safe], &percent/1)]

    Mix.shell().info("\nEvents, #{strategy}")
    print_table(~w(event met success died safe), rows)
  end

  defp print_table(header, rows) do
    widths =
      [header | rows]
      |> Enum.zip_with(fn column -> column |> Enum.map(&String.length("#{&1}")) |> Enum.max() end)

    for row <- [header | rows] do
      row
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {cell, width} -> String.pad_trailing("#{cell}", width) end)
      |> String.trim_trailing()
      |> Mix.shell().info()
    end
  end

  defp strategies(nil), do: @strategies
  defp strategies(strategy) when strategy in @strategies, do: [strategy]

  defp strategies(strategy),
    do: Mix.raise("Unknown strategy #{strategy}, expected one of #{Enum.join(@strategies, ", ")}")

  defp route(nil), do: nil

  # event names map to atoms only through the known events, never String.to_atom
  defp route(route) do
    known = Map.new(Raid.events(), &{Atom.to_string(&1), &1})

    for name <- String.split(route, ",", trim: true) do
      Map.get(known, String.trim(name)) ||
        Mix.raise(
          "Unknown event #{name}, expected one of #{known |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
        )
    end
  end

  defp names("ru"), do: {Names.first_names_ru(), Names.last_names_ru()}
  defp names("en"), do: {Names.first_names_en(), Names.last_names_en()}
  defp names("de"), do: {Names.first_names_de(), Names.last_names_de()}
  defp names("ja"), do: {Names.first_names_ja(), Names.last_names_ja()}
  defp names(locale), do: Mix.raise("Unknown locale #{locale}, expected ru, en, de or ja")

  defp share(list, fun), do: Enum.count(list, fun) * 100 / max(length(list), 1)
  defp average(numbers), do: Enum.sum(numbers) / max(length(numbers), 1)

  defp percent(value), do: "#{:erlang.float_to_binary(value * 1.0, decimals: 1)}%"
  defp number(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)
end
