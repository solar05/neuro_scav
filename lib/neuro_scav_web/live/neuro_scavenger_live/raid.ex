defmodule NeuroScavWeb.NeuroScavengerLive.Raid do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  import NeuroScavWeb.RaidComponents

  alias NeuroScav.{Locale, Raid, RaidStore, ScavengersServer}
  alias NeuroScav.Raid.Report

  @max_name_length 40
  # the ways a death is told: "Raid lost %{name}" and "Raid death n %{name}" for n in 1..19
  @deaths 20
  @daytime_icons %{
    morning: "tabler-sunrise",
    day: "tabler-sun-high",
    evening: "tabler-sunset",
    night: "tabler-moon"
  }
  @weather_icons %{
    clear: "tabler-sun",
    fog: "tabler-cloud-fog",
    rain: "tabler-cloud-rain",
    wind: "tabler-wind",
    blizzard: "tabler-snowflake",
    heat: "tabler-flame",
    storm: "tabler-cloud-storm"
  }
  # characters of an outcome (with its notes) past which it takes a smaller font
  @long_outcome 100
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

  # the exit the squad got out through, nil when it didn't
  defp exit_text(raid) do
    event = Raid.at(raid) && raid.map.nodes[Raid.at(raid)]

    if (Raid.alive(raid) != [] and event) && Raid.exit?(event),
      do: gettext("Raid exited %{exit}", exit: event_title(event))
  end

  # how many items a member found: their loot works for them alone
  defp loot_count(raid, member), do: Enum.count(raid.stash, &(&1.owner == member.index))

  # View helpers

  defp option_label(_event, %{camp: rest}) when rest != nil,
    do: Locale.get_text("Raid camp #{rest}")

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

  # why an option can't be taken: nothing for a rest to do, the item a key
  # needs, or enough of running
  defp locked_text(%{camp: :heal}), do: gettext("Raid camp nobody wounded")
  defp locked_text(%{camp: :repack}), do: gettext("Raid camp nothing to repack")

  defp locked_text(%{key: key}) when key != nil,
    do: gettext("Raid needs %{item}", item: item_name(key))

  defp locked_text(%{pay: true}), do: gettext("Raid needs payment")

  defp locked_text(%{trust: level}) when level != nil,
    do: gettext("Raid needs karma %{value}", value: level)

  defp locked_text(_retreat), do: gettext("Raid retreat locked")

  # an option with no check, item, condition or rest: safe, or leaving a search
  defp plain?(option),
    do:
      option.stat == nil and option.key == nil and option.search == nil and not option.pay and
        option.trust == nil and option.camp == nil and not option.locked

  # the location, the time of day and the weather, each with its icon, in a line
  # with the checks they ease and harden now
  defp world_parts(raid) do
    %{daytime: daytime, weather: weather} = Raid.world(raid)

    Enum.filter(
      [
        location_name(raid) && {"tabler-map-pin", location_name(raid)},
        {@daytime_icons[daytime], Locale.get_text("Raid daytime #{daytime}")},
        {@weather_icons[weather], Locale.get_text("Raid weather #{weather}")}
      ],
      & &1
    )
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
  defp outcome_text(%{outcome: :repacked}), do: gettext("Raid repacked")

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

  # what else the last step brought, under what came of it
  defp outcome_notes(last) do
    Enum.filter(
      [last.follow_up && gettext("Raid follow up"), karma_note(last), used_note(last)],
      & &1
    )
  end

  # an outcome long enough to take a smaller font, to keep to its box
  defp outcome_long?(last) do
    [quirk_note(last), outcome_text(last) | outcome_notes(last)]
    |> Enum.map(&String.length(&1 || ""))
    |> Enum.sum() > @long_outcome
  end

  # the key or the consumable the step used (a spared member's tells it already)
  defp used_note(%{used: item, outcome: outcome}) when item != nil and outcome != :spared,
    do: gettext("Raid used %{item}", item: item_name(item))

  defp used_note(_last), do: nil

  # the check's roll against its chance, "34 ≤ 41" (a success, unless a lucky
  # one's failure came off); a check by each, the roll alone
  defp roll_text(%{roll: roll, chance: nil}), do: "#{roll}"
  defp roll_text(%{roll: roll, chance: chance}) when roll <= chance, do: "#{roll} ≤ #{chance}"
  defp roll_text(%{roll: roll, chance: chance}), do: "#{roll} > #{chance}"

  defp set_label(set), do: Locale.get_text("Set #{set}")

  defp karma_text(0), do: gettext("Raid karma %{value}", value: 0)
  defp karma_text(karma), do: gettext("Raid karma %{value}", value: signed(karma))

  defp outcome_class(%{outcome: outcome})
       when outcome in [
              :pass,
              :loot,
              :found,
              :revive,
              :train,
              :heal,
              :spared,
              :trusted,
              :repacked
            ],
       do: "raid-outcome-good"

  defp outcome_class(%{outcome: outcome}) when outcome in [:promote, :trophy],
    do: "raid-outcome-rare"

  defp outcome_class(%{outcome: outcome}) when outcome in [:lose, :drop, :wound, :wounds, :stall],
    do: "raid-outcome-bad"

  defp outcome_class(_last), do: nil

  defp verdict(raid), do: verdict_text(length(Raid.alive(raid)), length(raid.squad))

  # what the squad carried out, and the link to a page telling how the raid went
  defp result_loot(raid), do: raid |> Report.new(nil) |> Map.fetch!(:loot) |> loot_text()
  defp share_path(raid, locale), do: ~p"/share/raid/#{Report.encode(Report.new(raid, locale))}"

  # "11–14"
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
