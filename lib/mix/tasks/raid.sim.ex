defmodule Mix.Tasks.Raid.Sim do
  @shortdoc "Simulates raids to tune their balance (development only)"

  @moduledoc """
  Plays many raids (`NeuroScav.Raid`) with random squads and prints how they
  end. A development tool for trying new raid mechanics: it runs from Mix, and
  Mix isn't part of a release, so it is never reachable from the site.

      mix raid.sim                              # 5000 raids per strategy
      mix raid.sim --runs 20000 --seed 42       # more raids, the same ones every time
      mix raid.sim --strategy greedy --events   # one strategy, with a table per event
      mix raid.sim --route pmc,veteran,labs     # a fixed route instead of a random map
      mix raid.sim --locale en                  # squads from English names

  At every event a strategy picks an option:

  - `cautious` - the safe option when there is one (leaving a search too),
    otherwise the best chance
  - `careful` - the best worth, as a player would weigh it: the chance of what
    a success brings against the cost of a failure (a death costs the most);
    the safe option is worth nothing either way
  - `greedy` - the best chance, never the safe option
  - `random` - any option

  Where the map forks a strategy goes by the kind of event it sees ahead
  (`Raid.kind/1`) and whether a member may be lost there (`Raid.deadly?/1`;
  nothing to go by where it can't see): the cautious one keeps off bosses,
  fights and red rings, the careful one off bosses and red rings, both make
  for a camp; the greedy one goes for bosses and loot, the random one
  anywhere. At a camp the careful one patches up the wounded, else trains.

  Squads are five random first and last names of the locale, rarity by the
  usual rules (`ScavengersServer.check_name/1`). Members act on their own as
  on the site: every choice has a quirk roll.
  """

  use Mix.Task

  alias NeuroScav.{Raid, ScavengersServer}
  alias NeuroScav.Scavengers.Names

  @requirements ["compile"]

  @strategies ~w(cautious careful greedy random)
  # how the careful strategy weighs what a check may bring and cost
  @gains %{loot: 1, train: 1, revive: 2, promote: 2, trophy: 3}
  @costs %{lose: 3, wound: 1, drop: 1, stall: 1}
  # how a strategy takes a kind of node ahead and a red ring (deadly), 0 unless listed
  @leanings %{
    "cautious" => %{boss: -3, fight: -2, gnome: -1, hazard: -1, deadly: -1, camp: 2},
    "careful" => %{boss: -2, fight: -1, loot: 1, search: 1, deadly: -1, camp: 1},
    "greedy" => %{boss: 3, rare: 2, loot: 2, search: 1},
    "random" => %{}
  }
  @switches [
    runs: :integer,
    strategy: :string,
    locale: :string,
    seed: :integer,
    route: :string,
    events: :boolean
  ]
  # outcomes a raid may or may not meet, shown as the share of raids with one
  @outcomes [:loot, :found, :train, :wound, :promote, :trophy, :revive, :drop, :stall]
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
  last_names}`, `route` a fixed route or nil for a random map each time.
  """
  @spec simulate(String.t(), pos_integer(), {[String.t()], [String.t()]}, [atom()] | nil) ::
          [{map(), [map()]}]
  def simulate(strategy, runs, {firsts, lasts}, route \\ nil) do
    for _ <- 1..runs do
      squad =
        for _ <- 1..@squad_size,
            do: ScavengersServer.check_name("#{Enum.random(firsts)} #{Enum.random(lasts)}")

      play(Raid.new(squad, route || Raid.random_map()), strategy, [])
    end
  end

  # an option that can't be taken or a node the squad can't go to leaves the
  # raid where it was: better to fail loudly than to stand there forever
  defp play(raid, strategy, log) do
    cond do
      Raid.over?(raid) ->
        {raid, Enum.reverse(log)}

      Raid.event(raid) ->
        index = pick(strategy, Raid.options(raid))

        next =
          Raid.choose(raid, index, :rand.uniform(100), Raid.random_item(), :rand.uniform(100))

        if next.turn == raid.turn,
          do: Mix.raise("#{strategy} took an option that can't be taken at #{Raid.event(raid)}")

        play(next, strategy, [next.last | log])

      true ->
        next = Raid.move(raid, way(strategy, raid))
        if next == raid, do: Mix.raise("#{strategy} went where the squad can't go")
        play(next, strategy, log)
    end
  end

  # the next node the strategy likes best by what it sees there, a random one of equals
  defp way(strategy, raid) do
    raid
    |> Raid.next_nodes()
    |> Enum.shuffle()
    |> Enum.max_by(&lure(@leanings[strategy], raid, &1))
  end

  # how much a node draws a strategy: nothing where it can't see
  defp lure(leaning, raid, node) do
    event = raid.map.nodes[node]
    deadly = if Raid.deadly?(event), do: Map.get(leaning, :deadly, 0), else: 0

    if Raid.sight(raid, node) == :hidden,
      do: 0,
      else: Map.get(leaning, Raid.kind(event), 0) + deadly
  end

  defp pick("cautious", options) do
    Enum.find_value(open(options), fn {option, index} ->
      (is_nil(option.stat) and is_nil(option.search)) && index
    end) ||
      best(options)
  end

  defp pick("careful", options) do
    options
    |> open()
    |> Enum.max_by(fn {option, _index} -> worth(option) end)
    |> elem(1)
  end

  defp pick("greedy", options), do: best(options)
  defp pick("random", options), do: options |> open() |> Enum.random() |> elem(1)

  # the options there are to take, with their indexes: a locked retreat isn't
  defp open(options),
    do: options |> Enum.with_index() |> Enum.reject(fn {option, _index} -> option.locked end)

  # a safe option (no chance) brings and costs nothing; a key is a sure chance
  defp worth(%{chance: nil}), do: 0

  defp worth(%{chance: chance, reward: reward, risk: risk}),
    do: chance * Map.get(@gains, reward, 0) - (100 - chance) * Map.get(@costs, risk, 0)

  # the best chance among the checks, keys and searches there are to take;
  # the first option where none has one
  defp best(options) do
    options
    |> open()
    |> Enum.reject(fn {option, _index} -> is_nil(option.chance) end)
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
