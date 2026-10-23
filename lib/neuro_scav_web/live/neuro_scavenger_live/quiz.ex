defmodule NeuroScavWeb.NeuroScavengerLive.Quiz do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{BattleRoom, Locale, ScavengersServer}

  @rarities [:legendary, :epic, :rare, :uncommon, :common]

  # Questions come at random: the rarity of a name, or which of two cards wins
  # a duel. Rarities are picked evenly, so the rare ones show up often.
  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)

    {:ok,
     assign(socket,
       user_locale: locale,
       rarities: @rarities,
       right: 0,
       total: 0,
       answer: nil,
       # random, so only once connected: the dead render would show another one
       question: if(connected?(socket), do: question(locale))
     )}
  end

  @impl true
  def handle_event(
        "answer",
        %{"answer" => answer},
        %{assigns: %{answer: nil, question: %{} = question}} = socket
      ) do
    right = if right?(question, answer), do: 1, else: 0

    {:noreply,
     socket
     |> assign(:answer, answer)
     |> update(:right, &(&1 + right))
     |> update(:total, &(&1 + 1))}
  end

  # double clicks after the answer
  def handle_event("answer", _params, socket), do: {:noreply, socket}

  def handle_event("next", _params, socket),
    do: {:noreply, assign(socket, question: question(socket.assigns.user_locale), answer: nil)}

  defp question(locale) do
    if :rand.uniform(2) == 1, do: rarity_question(locale), else: duel_question(locale)
  end

  defp rarity_question(locale) do
    rarity = Enum.random(@rarities)
    %{type: :rarity, name: ScavengersServer.random_name(locale, rarity), rarity: rarity}
  end

  # two different rarities, so the rules give a hint; draws are dealt again
  defp duel_question(locale) do
    cards =
      @rarities
      |> Enum.take_random(2)
      |> Enum.map(&BattleRoom.card(%{name: ScavengersServer.random_name(locale, &1), rarity: &1}))

    case BattleRoom.compare(0, [Enum.at(cards, 0)], 1, [Enum.at(cards, 1)]) do
      %{winner: :draw} ->
        duel_question(locale)

      %{winner: winner, rounds: [rounds]} ->
        %{type: :duel, cards: cards, winner: winner, won: [won(rounds, 0), won(rounds, 1)]}
    end
  end

  defp won(rounds, side), do: for({stat, ^side} <- rounds, do: stat)

  defp correct(%{type: :rarity, rarity: rarity}), do: Atom.to_string(rarity)
  defp correct(%{type: :duel, winner: winner}), do: Integer.to_string(winner)

  defp right?(question, answer), do: answer == correct(question)

  # after the answer: the right option is marked, and the wrong pick if there was one
  defp answer_class(_question, nil, _option), do: nil

  defp answer_class(question, answer, option) do
    cond do
      option == correct(question) -> "quiz-right"
      option == answer -> "quiz-wrong"
      true -> nil
    end
  end

  defp rarity_label(rarity), do: Locale.get_text("Stats #{rarity}")
  defp rarity_text(rarity), do: Locale.get_text(Atom.to_string(rarity))
  defp rarity_rule(rarity), do: Locale.get_text("#{rarity} rule")
end
