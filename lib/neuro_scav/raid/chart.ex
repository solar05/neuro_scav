defmodule NeuroScav.Raid.Chart do
  @moduledoc """
  A raid's map: nodes `{layer, column}` in layers, each node linked to one
  or two of the next layer's, the last layer's to none. A map is `%{nodes:
  %{id => event}, links: %{id => [id]}}`, a random one (`random_map/1`) with
  the `location` it is too.

  A random map is one of Tarkov's locations (`locations/0`): its exits on the
  last layer, its bosses, and its own events turn up there more often
  (`@local_weight` times). Events are drawn by weight (`draw/3`): the
  promoting ones are rare. With `@boss_chance` a map gets one of the
  location's bosses, in the middle or just before the exits, where there's
  another way past if the map has one.
  """

  alias NeuroScav.Raid.Catalog

  @width 4
  # how many layers a map has, the exits' too
  @steps 10..13
  # how many walks across the map shape it, see shape/2
  @paths 3..4
  @boss_chance 0.8

  @catalog Catalog.compiled()
  # location => its exits, bosses and own events; those turn up there this much more often
  @locations @catalog.locations
  @local_weight 4
  @weights @catalog.weights
  # what a random map's nodes are drawn from, apart from its exits and boss
  @common @catalog.common

  @doc "How many layers a map has, the exits' too: the events a way across meets."
  @spec steps() :: Range.t()
  def steps, do: @steps

  @doc "Every location a random map may be."
  @spec locations() :: [atom()]
  def locations, do: Map.keys(@locations)

  @doc """
  A random map of `location` (a random one by default), as many layers long
  as `steps/0` picks: the location's exits on the last, different events
  everywhere else, drawn by weight, so rare events seldom show up and the
  location's own often do. Bosses and chain events aren't drawn: with
  `@boss_chance` one of the location's bosses takes a node in the middle or
  just before the exits.
  """
  @spec random_map(atom() | nil) :: map()
  def random_map(location \\ nil) do
    location = location || Enum.random(locations())
    %{exits: exits, bosses: bosses, events: own} = Map.fetch!(@locations, location)
    weights = Map.merge(@weights, Map.new(own, &{&1, Map.get(@weights, &1, 1) * @local_weight}))

    layers = Enum.random(@steps)
    links = shape(layers, Enum.random(@paths))
    {ends, inner} = links |> Map.keys() |> Enum.split_with(&(elem(&1, 0) == layers - 1))
    boss = if :rand.uniform() < @boss_chance, do: boss_node(inner, layers)
    rest = Enum.shuffle(inner -- [boss])

    nodes =
      Enum.zip(rest, draw(@common, weights, length(rest))) ++
        Enum.zip(ends, Enum.take_random(exits, length(ends))) ++
        if(boss, do: [{boss, Enum.random(bosses)}], else: [])

    %{nodes: Map.new(nodes), links: links, location: location}
  end

  # a node in the middle layer or the one before the exits, where there's
  # another way past if it can be
  defp boss_node(ids, layers) do
    places = Enum.filter(ids, &(elem(&1, 0) in [div(layers, 2), layers - 2]))

    wide =
      Enum.filter(places, fn {layer, _column} ->
        Enum.count(ids, &(elem(&1, 0) == layer)) > 1
      end)

    Enum.random(if wide != [], do: wide, else: places)
  end

  @doc """
  `count` different keys, each with a chance by its weight (1 unless listed
  in `weights`): keys `u^(1/weight)`, the largest win.
  """
  @spec draw([term()], %{term() => number()}, non_neg_integer()) :: [term()]
  def draw(keys, weights, count) do
    keys
    |> Enum.sort_by(&(-:math.pow(:rand.uniform(), 1 / Map.get(weights, &1, 1))))
    |> Enum.take(count)
  end

  @doc "The nodes one can get to from `from` (that one too) along the map's links."
  @spec reachable(map(), tuple()) :: MapSet.t()
  def reachable(map, from), do: reach(map.links, [from], MapSet.new())

  defp reach(_links, [], reached), do: reached

  defp reach(links, [id | rest], reached) do
    if id in reached,
      do: reach(links, rest, reached),
      else: reach(links, links[id] ++ rest, MapSet.put(reached, id))
  end

  @doc "How many columns a map has."
  @spec width() :: pos_integer()
  def width, do: @width

  @doc "A map walking `events` one after another: a node a layer."
  @spec linear([atom()]) :: map()
  def linear(events) do
    ids = for layer <- 0..(length(events) - 1)//1, do: {layer, 0}
    nexts = Enum.map(Enum.drop(ids, 1), &[&1]) ++ [[]]

    %{nodes: Map.new(Enum.zip(ids, events)), links: Map.new(Enum.zip(ids, nexts))}
  end

  @doc """
  The links of a random shape `layers` long: `paths` walks from the first
  layer to the last, each from a random column and a column to either side at
  most a layer, never across a link already there (as in Slay the Spire).
  """
  @spec shape(pos_integer(), pos_integer()) :: %{tuple() => [tuple()]}
  def shape(layers, paths) do
    links = Enum.reduce(1..paths, %{}, fn _path, links -> walk(links, layers) end)
    ends = for {_from, nexts} <- links, id <- nexts, into: %{}, do: {id, []}

    ends |> Map.merge(links) |> Map.new(fn {id, nexts} -> {id, Enum.sort(nexts)} end)
  end

  defp walk(links, layers) do
    start = {0, Enum.random(0..(@width - 1))}

    {links, _end} =
      Enum.reduce(1..(layers - 1)//1, {links, start}, fn layer, {links, from} ->
        to = {layer, elem(from, 1) + side(links, from)}
        {Map.update(links, from, [to], &Enum.uniq([to | &1])), to}
      end)

    links
  end

  # straight on or a column aside, within the map and not across a link from
  # the neighbour passed by (it would lead where this one starts)
  defp side(links, {layer, column}) do
    -1..1
    |> Enum.filter(fn side ->
      (column + side) in 0..(@width - 1) and
        (side == 0 or {layer + 1, column} not in Map.get(links, {layer, column + side}, []))
    end)
    |> Enum.random()
  end

  @doc "The nodes a raid may start from: the first layer's."
  @spec starts(map()) :: [tuple()]
  def starts(map), do: map.nodes |> Map.keys() |> Enum.filter(&(elem(&1, 0) == 0)) |> Enum.sort()

  @doc "How many layers a map has: the last is its end."
  @spec layers(map()) :: pos_integer()
  def layers(map),
    do: map.nodes |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.max() |> Kernel.+(1)
end
