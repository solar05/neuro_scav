defmodule NeuroScav.Raid.Chart do
  @moduledoc """
  The shape of a raid's map: nodes `{layer, column}` in layers, each node
  linked to one or two of the next layer's, the last layer's to none. A map
  is `%{nodes: %{id => event}, links: %{id => [id]}}`; `NeuroScav.Raid` puts
  the events on its nodes.
  """

  @width 4

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
