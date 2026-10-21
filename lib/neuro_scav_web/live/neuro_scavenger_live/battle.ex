defmodule NeuroScavWeb.NeuroScavengerLive.Battle do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{BattleRoom, Locale, PubSub}

  @bot BattleRoom.bot()

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
        closed: false
      )

    {:ok, join(socket)}
  end

  # joins only over the socket: link previews (Telegram, etc.) must not take the second seat
  defp join(%{assigns: %{room_id: id}} = socket) when is_binary(id) do
    if connected?(socket) do
      PubSub.subscribe_battle(id)

      case BattleRoom.join(id, socket.assigns.user_id) do
        {:ok, battle} -> assign(socket, :battle, battle)
        {:error, :not_found} -> assign(socket, :closed, true)
      end
    else
      socket
    end
  end

  defp join(socket), do: socket

  @impl true
  def handle_event("create", _params, socket) do
    {:ok, id} = BattleRoom.create(socket.assigns.user_id)
    {:noreply, push_navigate(socket, to: ~p"/battle/#{id}")}
  end

  def handle_event("create_bot", _params, %{assigns: assigns} = socket) do
    {:ok, id} = BattleRoom.create_with_bot(assigns.user_id, assigns.user_locale)
    {:noreply, push_navigate(socket, to: ~p"/battle/#{id}")}
  end

  def handle_event("draw", _params, %{assigns: assigns} = socket),
    do: act(socket, BattleRoom.draw(assigns.room_id, assigns.user_id, assigns.user_locale))

  def handle_event("ready", _params, %{assigns: assigns} = socket),
    do: act(socket, BattleRoom.ready(assigns.room_id, assigns.user_id))

  def handle_event("rematch", _params, %{assigns: assigns} = socket),
    do: act(socket, BattleRoom.rematch(assigns.room_id, assigns.user_id))

  defp act(socket, {:ok, battle}), do: {:noreply, assign(socket, :battle, battle)}
  defp act(socket, {:error, :not_found}), do: {:noreply, assign(socket, :closed, true)}
  # double clicks and stale buttons: the broadcast state is already the truth
  defp act(socket, {:error, _reason}), do: {:noreply, socket}

  @impl true
  def handle_info({:battle_updated, battle}, socket),
    do: {:noreply, assign(socket, :battle, battle)}

  def handle_info(:battle_closed, socket),
    do: {:noreply, assign(socket, closed: true, battle: nil)}

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
    card: nil,
    ready?: false,
    can_draw?: false,
    can_fight?: false,
    won: [],
    score: nil,
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

  # before the reveal only the viewer's own card is rendered
  defp seat_state(%{result: nil} = battle, %{player: player, own?: own?} = seat) do
    card = battle.cards[player]

    %{
      seat
      | card: if(own?, do: card),
        ready?: player in battle.ready,
        can_draw?: own? and (card == nil or player not in battle.redrawn),
        can_fight?: own? and card != nil and player not in battle.ready
    }
  end

  defp seat_state(%{result: result} = battle, %{player: player} = seat) do
    %{
      seat
      | card: battle.cards[player],
        won: for({stat, ^player} <- result.rounds, do: stat),
        score: result.score[player],
        outcome: outcome(result, player)
    }
  end

  defp seat_label(_battle, nil, _user_id), do: gettext("Opponent")
  defp seat_label(_battle, player, player), do: gettext("You")

  defp seat_label(_battle, @bot, _user_id), do: gettext("Bot")

  defp seat_label(battle, player, user_id) do
    if player?(battle, user_id),
      do: gettext("Opponent"),
      else: gettext("Player %{n}", n: Enum.find_index(battle.players, &(&1 == player)) + 1)
  end

  defp outcome(%{winner: :draw}, _player), do: :draw
  defp outcome(%{winner: player}, player), do: :won
  defp outcome(_result, _player), do: :lost

  defp result_text(%{result: %{winner: :draw}}, _user_id), do: gettext("Draw result")

  defp result_text(%{result: %{winner: winner}} = battle, user_id) do
    cond do
      winner == user_id -> gettext("Victory")
      player?(battle, user_id) -> gettext("Defeat")
      true -> gettext("Winner %{name}", name: battle.cards[winner].name)
    end
  end

  defp stat_label(stat), do: Locale.get_text("Stat #{stat}")
  defp rarity_text(rarity), do: Locale.get_text(Atom.to_string(rarity))
end
