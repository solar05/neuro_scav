defmodule NeuroScavWeb.NeuroScavengerLive.Raid do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{Locale, Raid, RaidStore, ScavengersServer}
  alias NeuroScav.Raid.Chart

  @max_name_length 40
  # what an option may bring and cost, each icon telling its meaning on hover,
  # all of them in the legend (see legend/1)
  @icons [
    loot: "💰",
    revive: "➕",
    train: "💪",
    promote: "⭐",
    trophy: "🏆",
    lose: "💀",
    drop: "🎒",
    wound: "🩸",
    stall: "🔁",
    retreat: "🏃"
  ]
  # the ways a death is told: "Raid lost %{name}" and "Raid death n %{name}" for n in 1..19
  @deaths 20
  @daytime_icons %{morning: "🌅", day: "☀️", evening: "🌇", night: "🌙"}
  @weather_icons %{
    clear: "🌤",
    fog: "🌫",
    rain: "🌧",
    wind: "💨",
    blizzard: "🌨",
    heat: "🔥",
    storm: "⛈"
  }
  # a member's trait on their card, telling what it is on hover (and in the legend)
  @trait_icons %{greedy: "🤑", coward: "🐔", chatty: "🗣", lucky: "🍀", psycho: "🤪"}
  # a node's kind of event on the map, in the legend's order; :hidden is a node not seen
  @kind_icons [
    boss: "☠️",
    exit: "🚪",
    fight: "⚔️",
    loot: "💰",
    search: "📦",
    scav: "🧢",
    gnome: "🍄",
    rare: "⭐",
    hazard: "⚠️",
    hidden: "❓"
  ]
  # the map's units between layers and between columns; a phone shows only
  # @near_layers layers around the squad
  @layer_gap 56
  @column_gap 40
  @near_layers 6
  # the runs a page keeps of those it started: the last few, for the back and
  # forward buttons; the older ones are forgotten, so no page fills the store
  @kept_runs 3

  # /raid?team=<token> brings the squad from the Team page, see path/1;
  # `run=<id>` names the page's raid, see handle_params/3
  @impl true
  def mount(params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)

    {:ok,
     assign(socket,
       user_locale: locale,
       user_id: session["user_id"],
       team: params["team"],
       members: decode(params["team"]),
       run: params["run"],
       # the runs this page started, the latest first, see start_run/3
       runs: [],
       raid: nil
     )}
  end

  # A page's raid is a run, named in its address and kept in RaidStore: a
  # reconnect or the browser's back and forward buttons come with a run and
  # get its raid, a fresh visit (no run) or another tab (another run) doesn't.
  # A new raid gets a new run, a forgotten run is the lobby (or a new raid of
  # the link's team).
  @impl true
  def handle_params(params, _uri, socket) do
    run = params["run"]

    {:noreply,
     cond do
       # the route is random, so only once connected: the dead render would show another one
       not connected?(socket) ->
         socket

       # a patch to the raid's own run, just started, changes nothing
       socket.assigns.raid != nil and run == socket.assigns.run ->
         socket

       saved = saved_run(socket.assigns.user_id, run) ->
         socket |> assign(team: params["team"]) |> assign(saved)

       team = decode(params["team"]) ->
         socket |> assign(team: params["team"]) |> start_run(team, true)

       true ->
         assign(socket, team: nil, members: nil, run: nil, raid: nil)
     end}
  end

  defp saved_run(user_id, run) when is_binary(user_id) and is_binary(run) do
    case RaidStore.get({user_id, run}) do
      nil -> nil
      saved -> Map.put(saved, :run, run)
    end
  end

  defp saved_run(_user_id, _run), do: nil

  # A raid the address starts (a team's link, a forgotten run of one) takes the
  # address's place in the history, so the back button leaves the page rather
  # than coming to the link and starting yet another raid; a raid the squad
  # starts is a new page in it.
  defp start_run(socket, members, replace) do
    run = Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
    {runs, forgotten} = Enum.split([run | socket.assigns.runs], @kept_runs)
    Enum.each(forgotten, &RaidStore.delete({socket.assigns.user_id, &1}))

    socket
    |> assign(run: run, runs: runs)
    |> assign_raid(members, Raid.new(members))
    |> push_patch(to: run_path(socket.assigns.team, run), replace: replace)
  end

  defp forget_run(%{assigns: %{run: nil}}), do: true
  defp forget_run(%{assigns: %{user_id: user_id, run: run}}), do: RaidStore.delete({user_id, run})

  defp run_path(nil, run), do: ~p"/raid?#{[run: run]}"
  defp run_path(team, run), do: ~p"/raid?#{[team: team, run: run]}"

  # every change of the raid is kept, so a reconnect picks it up
  defp assign_raid(socket, members, raid) do
    RaidStore.put({socket.assigns.user_id, socket.assigns.run}, members, raid)
    assign(socket, members: members, raid: raid)
  end

  @doc "The raid page for a team: its names travel in the link, rarities are worked out again."
  @spec path([map()]) :: String.t()
  def path(team),
    do: "/raid?team=" <> Base.url_encode64(Enum.map_join(team, "\n", & &1.name), padding: false)

  defp decode(token) when is_binary(token) do
    with {:ok, names} <- Base.url_decode64(token, padding: false),
         [_ | _] = members <- names |> String.split("\n") |> Enum.flat_map(&member/1) do
      Enum.take(members, ScavengersServer.max_team_members())
    else
      _invalid -> nil
    end
  end

  defp decode(_token), do: nil

  defp member(name) do
    case name |> String.trim() |> String.slice(0, @max_name_length) do
      "" ->
        []

      name ->
        [
          if(name == gnome_name(),
            do: %{name: name, rarity: :gnome},
            else: ScavengersServer.check_name(name)
          )
        ]
    end
  end

  defp gnome_name, do: Locale.get_text("Gnome catched")

  # a new raid of the squad's own forgets the page's previous one: however many
  # it starts, a page keeps one in the store (one the address starts forgets
  # nothing: the back and forward buttons may still come to it)
  defp new_raid("recruit", socket) do
    members =
      for _ <- 1..ScavengersServer.max_team_members(),
          do: ScavengersServer.generate_uncounted(socket.assigns.user_locale)

    forget_run(socket)
    socket |> assign(team: nil) |> start_run(members, false)
  end

  defp new_raid("again", %{assigns: %{members: nil}} = socket), do: socket

  defp new_raid("again", socket) do
    forget_run(socket)
    start_run(socket, socket.assigns.members, false)
  end

  # a new raid comes from the lobby or once a raid is over: one under way is
  # left with "leave", never dropped for a new one
  @impl true
  def handle_event(event, _params, %{assigns: %{raid: raid}} = socket)
      when event in ["recruit", "again"] do
    if raid && not Raid.over?(raid),
      do: {:noreply, socket},
      else: {:noreply, new_raid(event, socket)}
  end

  # the squad leaves the raid: it's forgotten, the page is back at the lobby
  def handle_event("leave", _params, socket) do
    forget_run(socket)

    {:noreply,
     socket
     |> assign(team: nil, members: nil, run: nil, raid: nil)
     |> push_patch(to: ~p"/raid")}
  end

  # the click names the turn it was made at: a late or a double one meant an
  # event that's gone (a stall's too, at the same step), and must not choose
  # for the next one
  def handle_event(
        "choose",
        %{"index" => index, "turn" => turn},
        %{assigns: %{raid: %{turn: current} = raid, members: members}} = socket
      ) do
    with {index, ""} <- Integer.parse(index),
         {^current, ""} <- Integer.parse(turn) do
      raid = Raid.choose(raid, index, :rand.uniform(100), Raid.random_item(), :rand.uniform(100))
      {:noreply, assign_raid(socket, members, raid)}
    else
      _invalid_or_stale -> {:noreply, socket}
    end
  end

  # the node names its layer and column, "3-1"; one the squad can't go to changes nothing
  def handle_event(
        "move",
        %{"node" => node},
        %{assigns: %{raid: %{} = raid, members: members}} = socket
      ) do
    with [layer, column] <- String.split(node, "-"),
         {layer, ""} <- Integer.parse(layer),
         {column, ""} <- Integer.parse(column),
         moved when moved != raid <- Raid.move(raid, {layer, column}) do
      {:noreply, assign_raid(socket, members, moved)}
    else
      _invalid_or_stale -> {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

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
      <span class="raid-stash-icon" aria-hidden="true">🎒</span>
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
            <span class="raid-legend-icon">{option_icon(key)}</span> {icon_meaning(key)}
          </li>
        </ul>
        <p class="raid-legend-title">{gettext("Raid traits")}</p>
        <ul id="raid-legend-traits" class="raid-stash-list">
          <li :for={trait <- Raid.traits()}>
            <span class="raid-legend-icon">{trait_icon(trait)}</span> {trait_tip(trait)}
          </li>
        </ul>
        <p class="raid-legend-title">{gettext("Raid map")}</p>
        <ul id="raid-legend-map" class="raid-stash-list">
          <li :for={kind <- kinds()}>
            <span class="raid-legend-icon">{kind_icon(kind)}</span> {kind_name(kind)}
          </li>
          <li><span class="raid-legend-icon">⭕</span> {gettext("Raid node deadly")}</li>
          <li>{gettext("Raid map about")}</li>
        </ul>
      </div>
    </div>
    """
  end

  defp hide_legend, do: JS.add_class("hidden", to: "#raid-legend")

  attr :raid, :map, required: true

  # the legend's button and how far across the map the squad is, in a panel's header
  defp panel_meta(assigns) do
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
  attr :class, :string, default: nil

  # The map as far as the squad can tell (Raid.sight/2): layers left to right,
  # the columns the map has top to bottom; the way taken in gold, the nodes it
  # may go to next take it there on a click.
  defp raid_map(assigns) do
    %{raid: raid, layers: layers} = assigns
    next = Raid.next_nodes(raid)
    {top, bottom} = raid.map.nodes |> Map.keys() |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    origin = {layers.first, top}

    nodes =
      for {{layer, _column} = id, event} <- Enum.sort(raid.map.nodes),
          layer in layers,
          do: map_node(raid, id, event, origin, id in next)

    links =
      for {{layer, _column} = from, nexts} <- raid.map.links,
          layer in layers,
          to <- nexts,
          elem(to, 0) in layers,
          do: {spot(from, origin), spot(to, origin), from in raid.path and to in raid.path}

    assigns =
      assign(assigns,
        nodes: nodes,
        links: links,
        width: Range.size(layers) * @layer_gap,
        height: (bottom - top + 1) * @column_gap
      )

    ~H"""
    <svg
      id={@id}
      class={["raid-map", @class]}
      viewBox={"0 0 #{@width} #{@height}"}
      role="img"
      aria-label={gettext("Raid map")}
    >
      <line
        :for={{{x1, y1}, {x2, y2}, taken} <- @links}
        x1={x1}
        y1={y1}
        x2={x2}
        y2={y2}
        class={["raid-link", taken && "raid-link-taken"]}
      />
      <g
        :for={node <- @nodes}
        class={["raid-node" | node.classes]}
        data-node={node.key}
        phx-click={node.next && "move"}
        phx-value-node={node.next && node.key}
      >
        <title>{node.title}</title>
        <circle cx={node.x} cy={node.y} r="16" />
        <text x={node.x} y={node.y}>{node.icon}</text>
      </g>
    </svg>
    """
  end

  defp map_node(raid, id, event, origin, next) do
    sight = Raid.sight(raid, id)
    {x, y} = spot(id, origin)

    %{
      key: node_key(id),
      x: x,
      y: y,
      icon: node_icon(sight, event),
      title: node_title(sight, event),
      next: next,
      classes: [
        id == Raid.at(raid) && "raid-node-at",
        id in raid.path && "raid-node-done",
        next && "raid-node-next",
        Raid.boss?(event) && "raid-node-boss",
        sight == :hidden && "raid-node-hidden",
        (sight != :hidden and Raid.deadly?(event)) && "raid-node-deadly"
      ]
    }
  end

  # where a node is drawn: the first layer shown at the left, the map's top column on top
  defp spot({layer, column}, {first, top}),
    do:
      {(layer - first) * @layer_gap + div(@layer_gap, 2),
       (column - top) * @column_gap + div(@column_gap, 2)}

  defp node_key({layer, column}), do: "#{layer}-#{column}"

  defp node_icon(:hidden, _event), do: kind_icon(:hidden)
  defp node_icon(_sight, event), do: kind_icon(Raid.kind(event))

  # a node's name, and that a member may be lost there when it shows
  defp node_title(:hidden, _event), do: kind_name(:hidden)

  defp node_title(sight, event) do
    name = if sight == :event, do: event_title(event), else: kind_name(Raid.kind(event))
    if Raid.deadly?(event), do: name <> " · " <> icon_meaning(:lose), else: name
  end

  defp kinds, do: Keyword.keys(@kind_icons)
  defp kind_icon(kind), do: Keyword.fetch!(@kind_icons, kind)
  defp kind_name(kind), do: Locale.get_text("Raid node #{kind}")

  # the whole map; on a phone a few layers round the squad, from the one it left
  defp all_layers(raid), do: 0..(Chart.layers(raid.map) - 1)

  defp near_layers(raid) do
    last = Chart.layers(raid.map) - 1
    first = (Raid.layer(raid) - 1) |> min(last - @near_layers + 1) |> max(0)
    first..min(first + @near_layers - 1, last)
  end

  # the exit the squad got out through, nil when it didn't
  defp exit_text(raid) do
    event = Raid.at(raid) && raid.map.nodes[Raid.at(raid)]

    if (Raid.alive(raid) != [] and event) && Raid.exit?(event),
      do: gettext("Raid exited %{exit}", exit: event_title(event))
  end

  attr :option, :map, required: true

  # an option's icons, each telling what it means on hover
  defp icons(assigns) do
    ~H"""
    <span class="raid-option-icons">
      <span
        :for={key <- option_icons(@option)}
        class="raid-icon"
        data-tip={icon_meaning(key)}
        aria-label={icon_meaning(key)}
      >
        {option_icon(key)}
      </span>
    </span>
    """
  end

  defp icon_keys, do: Keyword.keys(@icons)
  defp option_icon(key), do: Keyword.fetch!(@icons, key)

  defp icon_meaning(:train), do: gettext("Raid icon train %{value}", value: Raid.stat_step())
  defp icon_meaning(:wound), do: gettext("Raid icon wound %{value}", value: Raid.stat_step())

  defp icon_meaning(:retreat),
    do: gettext("Raid icon retreat %{limit}", limit: Raid.retreat_limit())

  defp icon_meaning(key), do: Locale.get_text("Raid icon #{key}")

  defp trait_icon(trait), do: Map.fetch!(@trait_icons, trait)

  defp trait_tip(trait),
    do:
      "#{Locale.get_text("Raid trait #{trait}")}: #{Locale.get_text("Raid trait #{trait} about")}"

  # the stash with the finder's name and whether they're still around (the item works)
  defp stash_entries(%{stash: stash, squad: squad}) do
    for %{item: item, owner: index} <- stash do
      owner = Enum.at(squad, index)
      %{item: item, owner: owner.name, alive: owner.alive}
    end
  end

  # how many items a member found: their loot works for them alone
  defp loot_count(raid, member), do: Enum.count(raid.stash, &(&1.owner == member.index))

  # View helpers

  defp event_title(event), do: Locale.get_text("Raid #{event}")
  defp event_text(event), do: Locale.get_text("Raid #{event} text")

  defp option_label(event, %{key: key}) when key != nil,
    do: Locale.get_text("Raid #{event} #{key}")

  defp option_label(event, %{pay: true}), do: Locale.get_text("Raid #{event} pay")

  defp option_label(event, %{trust: level}) when level != nil,
    do: Locale.get_text("Raid #{event} karma")

  defp option_label(_event, %{search: 0}), do: gettext("Raid search")

  defp option_label(_event, %{search: looks}) when is_integer(looks),
    do: gettext("Raid search again")

  defp option_label(_event, %{leave: true}), do: gettext("Raid search leave")
  defp option_label(_event, %{stat: nil}), do: gettext("Raid pass by")
  defp option_label(event, %{stat: stat}), do: Locale.get_text("Raid #{event} #{stat}")

  # who makes the check: the best one (by name), the weakest, or every one
  defp performer(%{mode: :each}), do: gettext("Raid check each")

  defp performer(%{mode: :weakest, member: member}),
    do: gettext("Raid check weakest %{name}", name: member.name)

  defp performer(%{member: member}), do: member.name

  # why an option can't be taken: the item a key needs, or enough of running
  defp locked_text(%{key: key}) when key != nil,
    do: gettext("Raid needs %{item}", item: item_name(key))

  defp locked_text(%{pay: true}), do: gettext("Raid needs payment")

  defp locked_text(%{trust: level}) when level != nil,
    do: gettext("Raid needs karma %{value}", value: level)

  defp locked_text(_retreat), do: gettext("Raid retreat locked")

  # an option with no check, item or condition: safe, or leaving a search
  defp plain?(option),
    do:
      option.stat == nil and option.key == nil and option.search == nil and not option.pay and
        option.trust == nil and not option.locked

  # the time of day and the weather in a line, with the checks they ease and harden now
  defp world_text(raid) do
    %{daytime: daytime, weather: weather} = Raid.world(raid)

    "#{@daytime_icons[daytime]} #{Locale.get_text("Raid daytime #{daytime}")} · " <>
      "#{@weather_icons[weather]} #{Locale.get_text("Raid weather #{weather}")}"
  end

  # "easier: hiding, agility; harder: fighting", a kind of check or a stat each
  defp world_effects(raid) do
    world = Raid.world(raid)
    effects = Enum.sort(world.daytime_kinds) ++ Enum.sort(world.weather_stats)
    easier = for {kind, value} <- effects, value > 0, do: Locale.get_text("Raid kind #{kind}")
    harder = for {kind, value} <- effects, value < 0, do: Locale.get_text("Raid kind #{kind}")

    [
      {easier, gettext("Raid easier %{list}", list: Enum.join(easier, ", "))},
      {harder, gettext("Raid harder %{list}", list: Enum.join(harder, ", "))}
    ]
    |> Enum.reject(fn {kinds, _text} -> kinds == [] end)
    |> Enum.map_join("; ", fn {_kinds, text} -> text end)
  end

  defp stat_label(stat), do: Locale.get_text("Stat #{stat}")

  # some loot takes a little too: "+15", "−5" (a real minus sign)
  defp signed(value) when value < 0, do: "−#{-value}"
  defp signed(value), do: "+#{value}"
  defp item_name(item), do: Locale.get_text("Item #{item}")

  defp item_bonus(item) do
    case Raid.loot_bonus(item) do
      %{strength: same, agility: same, luck: same} ->
        gettext("Item all bonus %{bonus}", bonus: same)

      bonus ->
        Enum.map_join(bonus, ", ", fn {stat, value} -> "#{signed(value)} #{stat_label(stat)}" end)
    end
  end

  # what happened at the last event
  defp outcome_text(%{outcome: :safe}), do: gettext("Raid passed")

  # a check by each nobody failed
  defp outcome_text(%{outcome: :pass, member: nil}), do: gettext("Raid all passed")

  defp outcome_text(%{outcome: :pass, member: name}),
    do: gettext("Raid success %{name}", name: name)

  defp outcome_text(%{outcome: :wounds, member: names, stat: stat}),
    do:
      gettext("Raid wounds %{names} %{stat} %{value}",
        names: names,
        stat: stat_label(stat),
        value: Raid.stat_step()
      )

  defp outcome_text(%{outcome: :heal, member: name}), do: gettext("Raid heal %{name}", name: name)

  defp outcome_text(%{outcome: :spared, member: name, used: item}),
    do: gettext("Raid spared %{name} %{item}", name: name, item: item_name(item))

  # a death is told one of @deaths ways, by who and where: the same at every render
  defp outcome_text(%{outcome: :lose, member: name} = last) do
    case :erlang.phash2({name, last.event, last.stat}, @deaths) do
      0 -> gettext("Raid lost %{name}", name: name)
      n -> Locale.get_text("Raid death #{n} %{name}", name: name)
    end
  end

  defp outcome_text(%{outcome: :nothing, member: name}),
    do: gettext("Raid nothing %{name}", name: name)

  defp outcome_text(%{outcome: :revive, member: name}),
    do: gettext("Raid revive %{name}", name: name)

  defp outcome_text(%{outcome: :train, member: name, stat: stat}),
    do:
      gettext("Raid train %{name} %{stat} %{value}",
        name: name,
        stat: stat_label(stat),
        value: Raid.stat_step()
      )

  # a search hurts the one digging through the boxes
  defp outcome_text(%{outcome: :wound, member: name, stat: stat, event: event}) do
    bindings = [name: name, stat: stat_label(stat), value: Raid.stat_step()]

    if Raid.search?(event),
      do: gettext("Raid caught %{name} %{stat} %{value}", bindings),
      else: gettext("Raid wound %{name} %{stat} %{value}", bindings)
  end

  defp outcome_text(%{outcome: :found, member: name, item: item}),
    do: gettext("Raid found %{name} %{item}", name: name, item: item_name(item))

  defp outcome_text(%{outcome: :left}), do: gettext("Raid left")

  defp outcome_text(%{outcome: :paid, member: name, item: item}),
    do: gettext("Raid paid %{name} %{item}", name: name, item: item_name(item))

  defp outcome_text(%{outcome: :trusted}), do: gettext("Raid trusted")

  defp outcome_text(%{outcome: :stall, member: name}),
    do: gettext("Raid stall %{name}", name: name)

  defp outcome_text(%{outcome: :promote, member: name}),
    do: gettext("Raid promote %{name}", name: name)

  # gnomes don't make anyone drop loot: they steal it
  defp outcome_text(%{outcome: :drop, event: event, member: name, item: item}) do
    case {Raid.gnome?(event), item} do
      {true, nil} -> gettext("Raid gnome stole nothing")
      {true, item} -> gettext("Raid gnome stole %{item}", item: item_name(item))
      {false, nil} -> gettext("Raid drop nothing %{name}", name: name)
      {false, item} -> gettext("Raid drop %{name} %{item}", name: name, item: item_name(item))
    end
  end

  defp outcome_text(%{outcome: :loot, member: name, item: item}),
    do:
      gettext("Raid success %{name}", name: name) <>
        " " <> gettext("Raid loot %{item}", item: item_name(item))

  defp outcome_text(%{outcome: :trophy, member: name, item: item}),
    do: gettext("Raid trophy %{name} %{item}", name: name, item: item_name(item))

  # what a member did on their own
  defp quirk_note(%{quirk: {quirk, name}}),
    do: Locale.get_text("Raid quirk #{quirk} %{name}", name: name)

  defp quirk_note(_last), do: nil

  # what the scavs made of the last choice
  defp karma_note(%{karma: change}) when change > 0, do: gettext("Raid karma up")
  defp karma_note(%{karma: change}) when change < 0, do: gettext("Raid karma down")
  defp karma_note(_last), do: nil

  # the key or the consumable the step used (a spared member's tells it already)
  defp used_note(%{used: item, outcome: outcome}) when item != nil and outcome != :spared,
    do: gettext("Raid used %{item}", item: item_name(item))

  defp used_note(_last), do: nil

  defp karma_text(0), do: gettext("Raid karma %{value}", value: 0)
  defp karma_text(karma), do: gettext("Raid karma %{value}", value: signed(karma))

  defp outcome_class(%{outcome: outcome})
       when outcome in [:pass, :loot, :found, :revive, :train, :heal, :spared, :trusted],
       do: "raid-outcome-good"

  defp outcome_class(%{outcome: outcome}) when outcome in [:promote, :trophy],
    do: "raid-outcome-rare"

  defp outcome_class(%{outcome: outcome}) when outcome in [:lose, :drop, :wound, :wounds, :stall],
    do: "raid-outcome-bad"

  defp outcome_class(_last), do: nil

  defp verdict(raid) do
    alive = length(Raid.alive(raid))
    total = length(raid.squad)

    cond do
      alive == total -> gettext("Raid clean")
      alive == 0 -> gettext("Raid failed")
      true -> gettext("Raid survived %{alive} %{total}", alive: alive, total: total)
    end
  end

  # the icons an option shows: what it brings and costs (a pass or nothing has
  # none), and a retreat is marked: only so many of them in a row
  defp option_icons(%{reward: reward, risk: risk, retreat: retreat}),
    do: Enum.filter([reward, risk, retreat && :retreat], &Keyword.has_key?(@icons, &1))

  # "10–13"
  defp steps_text, do: "#{Raid.steps().first}–#{Raid.steps().last}"

  # the member the last event changed flashes: up, down, a promotion or a death
  defp member_change(%{last: %{index: index, outcome: outcome}}, %{index: index}) do
    case outcome do
      promoted when promoted in [:promote, :trophy] -> "raid-member-promoted"
      up when up in [:train, :revive, :loot, :found, :heal, :spared] -> "raid-member-up"
      down when down in [:wound, :wounds] -> "raid-member-down"
      :lose -> "raid-member-killed"
      _other -> nil
    end
  end

  defp member_change(_raid, _member), do: nil
end
