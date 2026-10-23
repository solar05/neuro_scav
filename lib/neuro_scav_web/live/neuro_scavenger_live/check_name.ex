defmodule NeuroScavWeb.NeuroScavengerLive.CheckName do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{BattleRoom, Locale, ScavengersServer}

  @max_name_length 40

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)

    {:ok,
     socket
     |> assign(:user_locale, locale)
     |> assign(:suggestions, nil)
     |> assign(:card, nil)
     |> assign(:scavenger, %{
       name: Locale.get_text("Check name title"),
       rarity: nil,
       rarity_text: Locale.get_text("default")
     })}
  end

  @impl true
  def handle_event("check_name", %{"name" => name}, socket) do
    name = name |> String.split() |> Enum.join(" ") |> String.slice(0, @max_name_length)

    # rarity rules compare first and last words, so a single word gets last name suggestions
    socket =
      case String.split(name) do
        [_first, _last | _] ->
          %{name: name, rarity: rarity} = scavenger = ScavengersServer.check_name(name)
          rarity_text = Locale.get_text(Atom.to_string(rarity))

          socket
          |> assign(:scavenger, %{name: name, rarity: rarity, rarity_text: rarity_text})
          |> assign(:card, BattleRoom.card(scavenger))

        [first] ->
          suggestions = ScavengersServer.suggest_last_names(first, socket.assigns.user_locale)
          assign(socket, :suggestions, %{first: first, groups: suggestions})

        [] ->
          socket
      end

    {:noreply, socket}
  end

  defp rarity_label(rarity), do: Locale.get_text("Stats #{rarity}")
end
