defmodule NeuroScavWeb.NeuroScavengerLive.Raid do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{Locale, Raid, RaidStore, ScavengersServer}

  @max_name_length 40
  # what an option may bring and cost, shown on its button (legend under the options)
  @reward_icons %{loot: "💰", revive: "➕", train: "💪", promote: "⭐", trophy: "🏆"}
  @risk_icons %{lose: "💀", drop: "🎒", wound: "🩸"}
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

  # the click names the step it was made at: a late or a double one meant an
  # event that's gone, and must not choose for the next one
  def handle_event(
        "choose",
        %{"index" => index, "step" => step},
        %{assigns: %{raid: %{step: current} = raid, members: members}} = socket
      ) do
    with {index, ""} <- Integer.parse(index),
         {^current, ""} <- Integer.parse(step) do
      {:noreply, assign_raid(socket, members, Raid.choose(raid, index, :rand.uniform(100)))}
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

  defp option_label(_event, %{path: path}) when path != nil, do: "→ " <> event_title(path)
  defp option_label(_event, %{stat: nil}), do: gettext("Raid pass by")
  defp option_label(event, %{stat: stat}), do: Locale.get_text("Raid #{event} #{stat}")

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

  defp outcome_text(%{outcome: :pass, member: name}),
    do: gettext("Raid success %{name}", name: name)

  defp outcome_text(%{outcome: :lose, member: name}), do: gettext("Raid lost %{name}", name: name)

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

  defp outcome_text(%{outcome: :wound, member: name, stat: stat}),
    do:
      gettext("Raid wound %{name} %{stat} %{value}",
        name: name,
        stat: stat_label(stat),
        value: Raid.stat_step()
      )

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

  defp outcome_text(%{outcome: :path, path: path}),
    do: gettext("Raid path %{event}", event: event_title(path))

  # what the scavs made of the last choice
  defp karma_note(%{karma: change}) when change > 0, do: gettext("Raid karma up")
  defp karma_note(%{karma: change}) when change < 0, do: gettext("Raid karma down")
  defp karma_note(_last), do: nil

  defp karma_text(0), do: gettext("Raid karma %{value}", value: 0)
  defp karma_text(karma), do: gettext("Raid karma %{value}", value: signed(karma))

  defp outcome_class(%{outcome: outcome}) when outcome in [:pass, :loot, :revive, :train],
    do: "raid-outcome-good"

  defp outcome_class(%{outcome: outcome}) when outcome in [:promote, :trophy],
    do: "raid-outcome-rare"

  defp outcome_class(%{outcome: outcome}) when outcome in [:lose, :drop, :wound],
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

  # a retreat is marked: only so many of them in a row
  defp option_icons(%{reward: reward, risk: risk, retreat: retreat}),
    do:
      [@reward_icons[reward], @risk_icons[risk], if(retreat, do: "🏃")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

  # "10–13"
  defp steps_text, do: "#{Raid.steps().first}–#{Raid.steps().last}"

  # the member the last event changed flashes: up, down, a promotion or a death
  defp member_change(%{last: %{index: index, outcome: outcome}}, %{index: index}) do
    case outcome do
      promoted when promoted in [:promote, :trophy] -> "raid-member-promoted"
      up when up in [:train, :revive, :loot] -> "raid-member-up"
      :wound -> "raid-member-down"
      :lose -> "raid-member-killed"
      _other -> nil
    end
  end

  defp member_change(_raid, _member), do: nil

  # route dots: done, current, ahead
  defp route_dot(raid, index) do
    cond do
      index < raid.step -> "raid-dot-done"
      index == raid.step and not Raid.over?(raid) -> "raid-dot-now"
      true -> nil
    end
  end
end
