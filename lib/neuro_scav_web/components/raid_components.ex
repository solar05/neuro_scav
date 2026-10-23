defmodule NeuroScavWeb.RaidComponents do
  @moduledoc """
  The raid page's parts (`NeuroScavWeb.NeuroScavengerLive.Raid`): the stash
  and the legend dialogs, a panel's header, the map (the card beside the
  event, a phone's strip and its dialog), an option's icons, and the names of
  what a raid is made of.
  """
  use NeuroScavWeb, :html

  alias NeuroScav.{Locale, Raid}
  alias NeuroScav.Raid.Chart

  # what an option may bring and cost, each icon telling its meaning on hover,
  # all of them in the legend (see legend/1)
  @icons [
    loot: "tabler-moneybag",
    revive: "tabler-heart-plus",
    train: "tabler-barbell",
    promote: "tabler-chevrons-up",
    trophy: "tabler-trophy",
    lose: "tabler-skull",
    drop: "tabler-backpack-off",
    wound: "tabler-droplet",
    stall: "tabler-repeat",
    retreat: "tabler-run"
  ]
  # a member's trait on their card, telling what it is on hover (and in the legend)
  @trait_icons %{
    greedy: "tabler-pig-money",
    coward: "tabler-mood-nervous",
    chatty: "tabler-message-circle",
    lucky: "tabler-clover",
    psycho: "tabler-mood-crazy-happy"
  }
  # a node's kind of event on the map (a Tabler icon, see tailwind.config.js),
  # in the legend's order; a node not seen shows none
  @kind_icons [
    boss: "tabler-skull",
    exit: "tabler-door-exit",
    fight: "tabler-swords",
    loot: "tabler-moneybag",
    search: "tabler-box",
    scav: "tabler-spy",
    gnome: "tabler-mushroom",
    rare: "tabler-star",
    hazard: "tabler-alert-triangle"
  ]
  # the map's pixels a layer and a column apart: the card has the layers going
  # up, a phone's strip going right, @strip_layers of them round the squad
  @gaps %{vertical: {34, 52}, horizontal: {62, 26}}
  @strip_layers 5

  @doc """
  The squad's loot: a narrow button beside the squad (always there, so the row
  doesn't jump when the first item turns up) and a compact modal in the middle
  of the screen. It opens and closes on the client (JS commands stay through
  patches); the backdrop is a sibling of the panel, so a click inside the panel
  keeps it open. Each item shows who found it: loot works for its finder only,
  so a fallen finder's items are dimmed and the button counts the active ones.
  """
  attr :loot, :list, required: true, doc: "%{item, owner, alive} each, see stash_entries/1"

  def stash(assigns) do
    ~H"""
    <button
      id="btn-raid-stash"
      type="button"
      class="btn btn-old-blended blended raid-stash-btn"
      phx-click={JS.remove_class("hidden", to: "#raid-stash")}
    >
      <.icon name="tabler-backpack" class="raid-stash-icon" />
      <span>{gettext("Stash")}</span>
      <b>{Enum.count(@loot, & &1.alive)}</b>
    </button>
    <div
      id="raid-stash"
      class="shortcuts-modal hidden"
      phx-window-keydown={hide_stash()}
      phx-key="Escape"
    >
      <div class="raid-stash-backdrop" phx-click={hide_stash()}></div>
      <div class="shortcuts-modal-content raid-stash">
        <div class="shortcuts-modal-header">
          <span>{gettext("Stash")}</span>
          <button type="button" class="shortcuts-modal-close" phx-click={hide_stash()}>X</button>
        </div>
        <ul :if={@loot != []} class="raid-stash-list">
          <li
            :for={%{item: item, owner: owner, alive: alive} <- @loot}
            class={not alive && "raid-stash-inactive"}
          >
            <b class={Raid.trophy_item?(item) && "raid-stash-trophy"}>{item_name(item)}</b>
            {item_bonus(item)}
            <span class={["raid-stash-owner", not alive && "raid-stash-owner-dead"]}>{owner}</span>
          </li>
        </ul>
        <p :if={@loot == []} class="raid-stash-empty">{gettext("Stash empty")}</p>
      </div>
    </div>
    """
  end

  defp hide_stash, do: JS.add_class("hidden", to: "#raid-stash")

  @doc """
  What the icons on the options, the traits and the map mean: a compact modal like the stash's, opened
  by the small button in the event's header (`#btn-raid-legend`), so the
  legend takes no room on the page. It sits outside the event's panel, which
  clips what it holds.
  """
  def legend(assigns) do
    ~H"""
    <div
      id="raid-legend"
      class="shortcuts-modal hidden"
      phx-window-keydown={hide_legend()}
      phx-key="Escape"
    >
      <div class="raid-stash-backdrop" phx-click={hide_legend()}></div>
      <div class="shortcuts-modal-content raid-stash">
        <div class="shortcuts-modal-header">
          <span>{gettext("Raid legend")}</span>
          <button type="button" class="shortcuts-modal-close" phx-click={hide_legend()}>X</button>
        </div>
        <ul class="raid-stash-list">
          <li :for={key <- icon_keys()}>
            <span class={["raid-legend-icon", "raid-icon-#{key}"]}>
              <.icon name={option_icon(key)} class="raid-legend-tabler" />
            </span>
            {icon_meaning(key)}
          </li>
        </ul>
        <p class="raid-legend-title">{gettext("Raid traits")}</p>
        <ul id="raid-legend-traits" class="raid-stash-list">
          <li :for={trait <- Raid.traits()}>
            <span class="raid-legend-icon">
              <.icon name={trait_icon(trait)} class="raid-legend-tabler" />
            </span>
            {trait_tip(trait)}
          </li>
        </ul>
        <p class="raid-legend-title">{gettext("Raid map")}</p>
        <ul id="raid-legend-map" class="raid-stash-list">
          <li :for={kind <- kinds()}>
            <span class={["raid-legend-icon", "raid-kind-#{kind}"]}>
              <.icon name={kind_icon(kind)} class="raid-legend-tabler" />
            </span>
            {kind_name(kind)}
          </li>
          <li>
            <span class="raid-legend-icon"><span class="raid-legend-dot"></span></span>
            {kind_name(:hidden)}
          </li>
          <li>
            <span class="raid-legend-icon"><span class="raid-legend-ring"></span></span>
            {gettext("Raid node deadly")}
          </li>
          <li>{gettext("Raid map about")}</li>
        </ul>
      </div>
    </div>
    """
  end

  defp hide_legend, do: JS.add_class("hidden", to: "#raid-legend")

  attr :raid, :map, required: true

  # the legend's button and how far across the map the squad is, in a panel's header
  def panel_meta(assigns) do
    ~H"""
    <span class="raid-event-meta">
      <button
        id="btn-raid-legend"
        type="button"
        class="raid-legend-btn"
        title={gettext("Raid legend")}
        aria-label={gettext("Raid legend")}
        phx-click={JS.remove_class("hidden", to: "#raid-legend")}
      >
        ?
      </button>
      <span class="wheel-panel-count">
        {gettext("Raid step %{n} %{total}",
          n: Raid.layer(@raid) + 1,
          total: Chart.layers(@raid.map)
        )}
      </span>
    </span>
    """
  end

  attr :raid, :map, required: true
  attr :id, :string, required: true
  attr :layers, Range, required: true, doc: "the layers shown"
  attr :orientation, :atom, values: [:vertical, :horizontal], required: true
  attr :closes, :string, default: nil, doc: "a dialog a move closes"
  attr :info, :string, default: nil, doc: "where a tap tells a node's name (no hover on a phone)"
  attr :class, :string, default: nil

  # The map as far as the squad can tell (Raid.sight/2): the way taken in
  # gold, red rings where a member may be lost, pale what's only remembered,
  # paler what's out of reach; the squad's node counts down the pursuers, the
  # nodes it may go to next take it there on a click. Nodes are buttons (a
  # tooltip, a hit area) over the links' SVG; the map keeps its pixel size
  # unless there's less room.
  def raid_map(assigns) do
    %{raid: raid, layers: layers, orientation: orientation} = assigns
    next = Raid.next_nodes(raid)
    reach = Raid.reachable(raid)
    {top, bottom} = raid.map.nodes |> Map.keys() |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    {layer_gap, column_gap} = @gaps[orientation]
    along = Range.size(layers) * layer_gap
    across = (bottom - top + 1) * column_gap
    size = if orientation == :vertical, do: {across, along}, else: {along, across}

    spots =
      for {{layer, _column} = id, _event} <- raid.map.nodes,
          layer in layers,
          into: %{},
          do: {id, spot(id, {layers, top}, orientation)}

    nodes =
      for {id, event} <- Enum.sort(raid.map.nodes),
          Map.has_key?(spots, id),
          do: map_node(raid, id, event, spots[id], size, {id in next, reach})

    links =
      for {from, nexts} <- raid.map.links,
          to <- nexts,
          spots[from] && spots[to],
          do: {curve(spots[from], spots[to], orientation), link_class(raid, reach, from, to)}

    assigns =
      assign(assigns, nodes: nodes, links: links, width: elem(size, 0), height: elem(size, 1))

    ~H"""
    <div
      id={@id}
      class={["raid-map", "raid-map-#{@orientation}", @class]}
      style={"width: #{@width}px; aspect-ratio: #{@width} / #{@height}"}
      role="group"
      aria-label={gettext("Raid map")}
    >
      <svg
        class="raid-map-links"
        viewBox={"0 0 #{@width} #{@height}"}
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        <path :for={{d, class} <- @links} d={d} class={["raid-link", class]} />
      </svg>
      <button
        :for={node <- @nodes}
        type="button"
        class={["raid-node" | node.classes]}
        style={"left: #{node.left}%; top: #{node.top}%"}
        data-node={node.key}
        data-tip={node.title}
        data-chase={node.chase}
        aria-label={node.title}
        tabindex={if !node.next, do: "-1"}
        phx-click={node_click(node, @closes, @info)}
      >
        <.icon :if={node.icon} name={node.icon} class="raid-node-icon" />
      </button>
    </div>
    """
  end

  # a node the squad may go to takes it there; another tells its name where a tap shows it
  defp node_click(%{next: true, key: key}, closes, _info), do: move(key, closes)

  defp node_click(%{title: title}, _closes, info) when info != nil,
    do: JS.set_attribute({"data-text", title}, to: info)

  defp node_click(_node, _closes, _info), do: nil

  defp move(key, nil), do: JS.push("move", value: %{node: key})
  defp move(key, dialog), do: key |> move(nil) |> JS.add_class("hidden", to: dialog)

  defp map_node(raid, id, event, {x, y}, {width, height}, {next, reach}) do
    sight = Raid.sight(raid, id)
    at = id == Raid.at(raid)

    %{
      key: node_key(id),
      left: Float.round(x * 100 / width, 2),
      top: Float.round(y * 100 / height, 2),
      icon: sight != :hidden && kind_icon(Raid.kind(event)),
      title: node_title(sight, event),
      next: next,
      chase: at && chase(raid),
      classes: [
        at && "raid-node-at",
        id in raid.path && "raid-node-done",
        next && "raid-node-next",
        (id not in reach and id not in raid.path) && "raid-node-gone"
        | sight_classes(sight, event)
      ]
    }
  end

  # the way taken, a way the squad can still take, or one it can't any more
  defp link_class(raid, reach, from, to) do
    cond do
      from in raid.path and to in raid.path -> "raid-link-taken"
      from in reach and to in reach -> nil
      true -> "raid-link-gone"
    end
  end

  # how many nodes on the nearest pursuer catches up, nil with none
  defp chase(%{pursuers: []}), do: nil
  defp chase(raid), do: raid.pursuers |> Enum.map(&max(elem(&1, 1), 1)) |> Enum.min()

  # what a node shows of its event: its kind, a boss, the danger (pale if
  # only remembered); or nothing
  defp sight_classes(:hidden, _event), do: ["raid-node-hidden"]

  defp sight_classes(:remembered, event),
    do: ["raid-node-remembered" | sight_classes(:kind, event)]

  defp sight_classes(_sight, event) do
    [
      "raid-kind-#{Raid.kind(event)}",
      Raid.boss?(event) && "raid-node-boss",
      Raid.deadly?(event) && "raid-node-deadly"
    ]
  end

  # Where a node is drawn: on the card the first layer at the bottom, on the
  # strip at the left, the map's top column first; a little off its layer's
  # line (the same at every render), so it's a map and not a table.
  defp spot({layer, column} = id, {layers, top}, orientation) do
    {layer_gap, column_gap} = @gaps[orientation]
    offset = :erlang.phash2(id, 9) - 4
    across = (column - top) * column_gap + div(column_gap, 2)

    case orientation do
      :vertical -> {across, (layers.last - layer) * layer_gap + div(layer_gap, 2) + offset}
      :horizontal -> {(layer - layers.first) * layer_gap + div(layer_gap, 2) + offset, across}
    end
  end

  # a link bends between two layers instead of cutting straight across
  defp curve({x1, y1}, {x2, y2}, :vertical),
    do: "M#{x1} #{y1} C#{x1} #{div(y1 + y2, 2)} #{x2} #{div(y1 + y2, 2)} #{x2} #{y2}"

  defp curve({x1, y1}, {x2, y2}, :horizontal),
    do: "M#{x1} #{y1} C#{div(x1 + x2, 2)} #{y1} #{div(x1 + x2, 2)} #{y2} #{x2} #{y2}"

  def node_key({layer, column}), do: "#{layer}-#{column}"

  # a node's name, and that a member may be lost there when it shows
  defp node_title(:hidden, _event), do: kind_name(:hidden)

  defp node_title(sight, event) do
    name = if sight == :event, do: event_title(event), else: kind_name(Raid.kind(event))
    if Raid.deadly?(event), do: name <> " · " <> icon_meaning(:lose), else: name
  end

  def kinds, do: Keyword.keys(@kind_icons)
  def kind_icon(kind), do: Keyword.fetch!(@kind_icons, kind)
  def kind_name(kind), do: Locale.get_text("Raid node #{kind}")

  # the whole map; on a phone's strip a few layers round the squad, from the one it left
  def all_layers(raid), do: 0..(Chart.layers(raid.map) - 1)

  def near_layers(raid) do
    last = Chart.layers(raid.map) - 1
    first = (Raid.layer(raid) - 1) |> min(last - @strip_layers + 1) |> max(0)
    first..min(first + @strip_layers - 1, last)
  end

  attr :raid, :map, required: true

  # under the whole map: why the dark hides it, and who's on the squad's trail
  def map_notes(assigns) do
    ~H"""
    <p :if={Raid.dark?(@raid)} class="raid-map-note">{dark_text(@raid)}</p>
    <p
      :for={{event, left} <- Enum.sort_by(@raid.pursuers, &elem(&1, 1))}
      class="raid-map-note raid-map-chase"
    >
      {gettext("Raid chase %{event} %{n}", event: event_title(event), n: max(left, 1))}
    </p>
    """
  end

  defp dark_text(%{weather: :fog}), do: gettext("Raid map fog")
  defp dark_text(_night), do: gettext("Raid map night")

  @doc """
  The whole map in a dialog, for a phone (the card beside the event is for a
  wide screen): opened by the button by the strip, closed by a move too; a
  tap on another node tells its name under the map.
  """
  attr :raid, :map, required: true

  def map_dialog(assigns) do
    ~H"""
    <div
      id="raid-map-dialog"
      class="shortcuts-modal hidden"
      phx-window-keydown={hide_map()}
      phx-key="Escape"
    >
      <div class="raid-stash-backdrop" phx-click={hide_map()}></div>
      <div class={["shortcuts-modal-content raid-stash raid-map-dialog", location_class(@raid)]}>
        <div class="shortcuts-modal-header">
          <span>{location_name(@raid) || gettext("Raid map")}</span>
          <button type="button" class="shortcuts-modal-close" phx-click={hide_map()}>X</button>
        </div>
        <.raid_map
          raid={@raid}
          id="raid-map-full"
          layers={all_layers(@raid)}
          orientation={:vertical}
          closes="#raid-map-dialog"
          info="#raid-map-info"
        />
        <p id="raid-map-info" class="raid-map-info"></p>
        <.map_notes raid={@raid} />
      </div>
    </div>
    """
  end

  defp hide_map, do: JS.add_class("hidden", to: "#raid-map-dialog")

  attr :option, :map, required: true

  # an option's icons, each telling what it means on hover
  def icons(assigns) do
    ~H"""
    <span class="raid-option-icons">
      <span
        :for={key <- option_icons(@option)}
        class={["raid-icon", "raid-icon-#{key}"]}
        data-tip={icon_meaning(key)}
        aria-label={icon_meaning(key)}
      >
        <.icon name={option_icon(key)} />
      </span>
    </span>
    """
  end

  def icon_keys, do: Keyword.keys(@icons)
  def option_icon(key), do: Keyword.fetch!(@icons, key)

  def icon_meaning(:train), do: gettext("Raid icon train %{value}", value: Raid.stat_step())
  def icon_meaning(:wound), do: gettext("Raid icon wound %{value}", value: Raid.stat_step())

  def icon_meaning(:retreat),
    do: gettext("Raid icon retreat %{limit}", limit: Raid.retreat_limit())

  def icon_meaning(key), do: Locale.get_text("Raid icon #{key}")

  def trait_icon(trait), do: Map.fetch!(@trait_icons, trait)

  def trait_tip(trait),
    do:
      "#{Locale.get_text("Raid trait #{trait}")}: #{Locale.get_text("Raid trait #{trait} about")}"

  # the stash with the finder's name and whether they're still around (the item works)
  def stash_entries(%{stash: stash, squad: squad}) do
    for %{item: item, owner: index} <- stash do
      owner = Enum.at(squad, index)
      %{item: item, owner: owner.name, alive: owner.alive}
    end
  end

  def event_title(event), do: Locale.get_text("Raid #{event}")
  def event_text(event), do: Locale.get_text("Raid #{event} text")

  # where the raid is, nil on a map of a test's own; its tint on the map's card and dialog
  def location_name(raid),
    do: if(location = Raid.location(raid), do: location_title(location))

  def location_title(location), do: Locale.get_text("Raid location #{location}")

  # how the squad came out of a raid, `alive` of `total`
  def verdict_text(alive, total) do
    cond do
      alive == total -> gettext("Raid clean")
      alive == 0 -> gettext("Raid failed")
      true -> gettext("Raid survived %{alive} %{total}", alive: alive, total: total)
    end
  end

  # the loot the squad carried out, or that it carried out nothing
  def loot_text([]), do: gettext("Raid result no loot")

  def loot_text(items),
    do: gettext("Raid result loot %{items}", items: Enum.map_join(items, ", ", &item_name/1))

  def location_class(raid),
    do: if(location = Raid.location(raid), do: "raid-location-#{location}")

  def stat_label(stat), do: Locale.get_text("Stat #{stat}")

  # some loot takes a little too: "+15", "−5" (a real minus sign)
  def signed(value) when value < 0, do: "−#{-value}"
  def signed(value), do: "+#{value}"
  def item_name(item), do: Locale.get_text("Item #{item}")

  # a member's rarity on their card: one member's, where the statistics count many
  def rarity_name(rarity), do: Locale.get_text("Raid rarity #{rarity}")

  def item_bonus(item) do
    case Raid.loot_bonus(item) do
      %{strength: same, agility: same, luck: same} ->
        gettext("Item all bonus %{bonus}", bonus: same)

      bonus ->
        Enum.map_join(bonus, ", ", fn {stat, value} -> "#{signed(value)} #{stat_label(stat)}" end)
    end
  end

  # the icons an option shows: what it brings and costs (a pass or nothing has
  # none), and a retreat is marked: only so many of them in a row
  defp option_icons(%{reward: reward, risk: risk, retreat: retreat}),
    do: Enum.filter([reward, risk, retreat && :retreat], &Keyword.has_key?(@icons, &1))
end
