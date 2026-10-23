defmodule NeuroScavWeb.NeuroScavengerLive.Battle do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{BattleRoom, Locale, PubSub}
  alias NeuroScavWeb.Presence

  @bot BattleRoom.bot()
  @modes %{"duel" => :duel, "team" => :team, "draft" => :draft}
  # open rooms whose owner is waiting on the page, keyed by room id
  @queue "battle_queue"

  # /battle is the lobby, /battle/:id the room behind an invite link
  @impl true
  def mount(params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)

    socket =
      assign(socket,
        user_locale: locale,
        user_id: Map.get(session, "user_id"),
        room_id: params["id"],
        battle: nil,
        closed: false,
        queued: false,
        mode: :duel
      )

    {:ok, join(socket)}
  end

  # joins only over the socket: link previews (Telegram, etc.) must not take the second seat
  defp join(%{assigns: %{room_id: id}} = socket) when is_binary(id) do
    if connected?(socket) do
      PubSub.subscribe_battle(id)

      case BattleRoom.join(id, socket.assigns.user_id) do
        {:ok, battle} -> socket |> assign(:battle, battle) |> queue()
        {:error, :not_found} -> assign(socket, :closed, true)
      end
    else
      socket
    end
  end

  defp join(socket), do: socket

  @impl true
  def handle_event("mode", %{"mode" => mode}, socket),
    do: {:noreply, assign(socket, :mode, Map.get(@modes, mode, :duel))}

  def handle_event("create", _params, %{assigns: assigns} = socket) do
    {:ok, id} =
      BattleRoom.create(assigns.user_id, mode: assigns.mode, locale: assigns.user_locale)

    {:noreply, push_navigate(socket, to: ~p"/battle/#{id}")}
  end

  def handle_event(
        "find",
        _params,
        %{assigns: %{user_id: user_id, mode: mode} = assigns} = socket
      ) do
    waiting = for {id, %{metas: [%{mode: ^mode} | _]}} <- Presence.list(@queue), do: id

    id =
      Enum.find(waiting, &seated?(BattleRoom.join(&1, user_id), user_id)) ||
        open_room(user_id, mode, assigns.user_locale)

    {:noreply, push_navigate(socket, to: ~p"/battle/#{id}")}
  end

  def handle_event("create_bot", _params, %{assigns: assigns} = socket) do
    {:ok, id} =
      BattleRoom.create_with_bot(assigns.user_id, assigns.user_locale, mode: assigns.mode)

    {:noreply, push_navigate(socket, to: ~p"/battle/#{id}")}
  end

  def handle_event("pick", %{"index" => index}, %{assigns: assigns} = socket) do
    case Integer.parse(index) do
      {index, ""} -> act(socket, BattleRoom.pick(assigns.room_id, assigns.user_id, index))
      _invalid -> {:noreply, socket}
    end
  end

  def handle_event("draw", _params, %{assigns: assigns} = socket),
    do: act(socket, BattleRoom.draw(assigns.room_id, assigns.user_id, assigns.user_locale))

  def handle_event("ready", _params, %{assigns: assigns} = socket),
    do: act(socket, BattleRoom.ready(assigns.room_id, assigns.user_id))

  def handle_event("rematch", _params, %{assigns: assigns} = socket),
    do: act(socket, BattleRoom.rematch(assigns.room_id, assigns.user_id))

  # another searcher may have taken the seat first, then the room just shows the battle
  defp seated?({:ok, battle}, user_id), do: player?(battle, user_id)
  defp seated?({:error, :not_found}, _user_id), do: false

  defp open_room(user_id, mode, locale) do
    {:ok, id} = BattleRoom.create(user_id, open: true, mode: mode, locale: locale)
    id
  end

  # Presence drops the entry by itself when the owner's page closes
  defp queue(%{assigns: %{battle: battle, user_id: user_id, queued: queued}} = socket) do
    waiting = match?(%{open: true, players: [^user_id]}, battle)

    cond do
      waiting and not queued -> Presence.track(self(), @queue, battle.id, %{mode: battle.mode})
      queued and not waiting -> Presence.untrack(self(), @queue, socket.assigns.room_id)
      true -> :ok
    end

    assign(socket, :queued, waiting)
  end

  defp act(socket, {:ok, battle}), do: {:noreply, assign(socket, :battle, battle)}
  defp act(socket, {:error, :not_found}), do: {:noreply, assign(socket, :closed, true)}
  # double clicks and stale buttons: the broadcast state is already the truth
  defp act(socket, {:error, _reason}), do: {:noreply, socket}

  @impl true
  def handle_info({:battle_updated, battle}, socket),
    do: {:noreply, socket |> assign(:battle, battle) |> queue()}

  def handle_info(:battle_closed, socket),
    do: {:noreply, socket |> assign(closed: true, battle: nil) |> queue()}

  # View helpers

  defp player?(battle, user_id), do: user_id in battle.players

  # the viewer's own seat goes first; spectators see player 1 on the left
  defp seats(%{players: players} = battle, user_id) do
    seats = Enum.take(players ++ [nil], 2)
    seats = if user_id == Enum.at(seats, 1), do: Enum.reverse(seats), else: seats

    seats
    |> Enum.with_index()
    |> Enum.map(fn {player, index} -> seat(battle, player, user_id, index) end)
  end

  @empty_seat %{
    index: nil,
    label: nil,
    player: nil,
    own?: false,
    cards: nil,
    sets: nil,
    ready?: false,
    can_draw?: false,
    can_fight?: false,
    score_steps: nil,
    outcome: nil
  }

  defp seat(battle, player, user_id, index) do
    seat = %{
      @empty_seat
      | index: index,
        label: seat_label(battle, player, user_id),
        player: player,
        own?: player != nil and player == user_id
    }

    seat_state(battle, seat)
  end

  defp seat_state(_battle, %{player: nil} = seat), do: seat

  # before the reveal only the viewer's own cards are rendered (a draft is open);
  # each card gets `won`, the stats it took in its pair
  defp seat_state(%{result: nil} = battle, %{player: player, own?: own?} = seat) do
    cards = battle.cards[player]
    open? = own? or battle.mode == :draft

    %{
      seat
      | cards: if(open? and cards, do: Enum.map(cards, &Map.put(&1, :won, []))),
        sets: if(open?, do: battle.sets[player]),
        ready?: player in battle.ready,
        can_draw?: can_draw?(battle, seat),
        can_fight?: can_fight?(battle, seat)
    }
  end

  defp seat_state(%{result: result} = battle, %{player: player} = seat) do
    won = Enum.map(result.rounds, fn rounds -> for {stat, ^player} <- rounds, do: stat end)

    %{
      seat
      | cards: Enum.zip_with(battle.cards[player], won, &Map.put(&1, :won, &2)),
        sets: battle.sets[player],
        score_steps: score_steps(result.rounds, player),
        outcome: outcome(result, player)
    }
  end

  # a ready card is final, as BattleRoom.draw/3 enforces; a draft has no draws
  defp can_draw?(%{mode: :draft}, _seat), do: false

  defp can_draw?(battle, %{player: player, own?: own?}) do
    own? and (not Map.has_key?(battle.cards, player) or player not in battle.redrawn) and
      player not in battle.ready
  end

  defp can_fight?(%{mode: :draft}, _seat), do: false

  defp can_fight?(battle, %{player: player, own?: own?}),
    do: own? and Map.has_key?(battle.cards, player) and player not in battle.ready

  defp seat_label(_battle, nil, _user_id), do: gettext("Opponent")
  defp seat_label(_battle, player, player), do: gettext("You")

  defp seat_label(_battle, @bot, _user_id), do: gettext("Bot")

  defp seat_label(battle, player, user_id) do
    if player?(battle, user_id),
      do: gettext("Opponent"),
      else: gettext("Player %{n}", n: Enum.find_index(battle.players, &(&1 == player)) + 1)
  end

  # what the other seat is up to, shown in its action row
  defp seat_status(_battle, %{player: nil}), do: gettext("Waiting for opponent")

  defp seat_status(%{mode: :draft} = battle, %{player: player}),
    do: if(BattleRoom.turn(battle) == player, do: gettext("Picking card"), else: "\u00a0")

  defp seat_status(_battle, %{ready?: true}), do: gettext("Card ready")
  defp seat_status(_battle, _seat), do: gettext("Drawing card")

  defp draft_note(battle, user_id) do
    if BattleRoom.turn(battle) == user_id,
      do: gettext("Your pick"),
      else: gettext("Opponent picks")
  end

  defp my_turn?(battle, user_id), do: BattleRoom.turn(battle) == user_id

  # unknown cards (and picks still to come in a draft) are placeholders
  defp pad(cards, size), do: Enum.take((cards || []) ++ List.duplicate(nil, size), size)

  defp rematch_offered?(battle, user_id), do: Enum.any?(battle.rematch, &(&1 != user_id))

  defp mode_label(:duel), do: "1 × 1"
  defp mode_label(:team), do: "3 × 3"
  defp mode_label(:draft), do: gettext("Draft")

  defp mode_rules(:team), do: gettext("Team battle rules")
  defp mode_rules(:draft), do: gettext("Draft rules")
  defp mode_rules(:duel), do: nil

  defp outcome(%{winner: :draw}, _player), do: :draw
  defp outcome(%{winner: player}, player), do: :won
  defp outcome(_result, _player), do: :lost

  # holds the line while there is no result yet
  defp result_text(%{result: nil}, _user_id), do: "\u00a0"
  defp result_text(%{result: %{winner: :draw}}, _user_id), do: gettext("Draw result")

  defp result_text(%{result: %{winner: winner}} = battle, user_id) do
    cond do
      winner == user_id -> gettext("Victory")
      player?(battle, user_id) -> gettext("Defeat")
      true -> gettext("Winner %{name}", name: hd(battle.cards[winner]).name)
    end
  end

  # The reveal lights the rounds up one by one (CSS delays of --round × --step),
  # then shows the outcome after --rounds steps. A duel's 3 rounds take 600ms
  # each, a team battle's 9 rounds 400ms each.
  defp reveal_style(%{size: size}) do
    rounds = size * length(BattleRoom.stats())
    "--rounds: #{rounds}; --step: #{min(600, div(3_600, rounds))}ms"
  end

  # the score as it grows during the reveal: {score, round it is reached in}
  defp score_steps(rounds, player) do
    winners = for slot <- rounds, stat <- BattleRoom.stats(), do: slot[stat]
    won_in = for {^player, round} <- Enum.with_index(winners), do: round
    [{0, 0} | Enum.with_index(won_in, fn round, won -> {won + 1, round} end)]
  end

  # battles won in this room in seat order, e.g. "2 : 1"
  defp series(battle, user_id),
    do: battle |> seats(user_id) |> Enum.map_join(" : ", &Map.get(battle.wins, &1.player, 0))

  defp stat_label(stat), do: Locale.get_text("Stat #{stat}")
  defp rarity_text(rarity), do: Locale.get_text(Atom.to_string(rarity))
  defp set_label(set), do: Locale.get_text("Set #{set}")
end
