defmodule NeuroScavWeb.NeuroScavengerLive.Neuro do
  use NeuroScavWeb, :live_view

  alias NeuroScav.{Locale, PubSub, StatsCounterServer}

  @turnstile Application.compile_env(:phoenix_turnstile, :adapter, Turnstile)

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")

    if connected?(socket) do
      Locale.setup_locale(Map.get(session, "lang"))
      PubSub.subscribe(:neuro_scavenger, session)
    end

    user_id = Map.get(session, "user_id")

    new_socket =
      socket
      |> assign(:neuro_scavenger, plain(Locale.get_text("Neuro placeholder")))
      |> assign(:user_locale, locale)
      |> assign(:user_id, user_id)

    {:ok, new_socket}
  end

  @impl true
  def handle_event("schedule_request", values, socket) do
    case @turnstile.verify(values) do
      {:ok, _} ->
        result =
          NeuroScav.UserRequestsServer.schedule_request(
            socket.assigns.user_id,
            socket.assigns.user_locale
          )

        message = format_schedule_message(result)

        {:noreply,
         socket
         |> assign(:neuro_scavenger, plain(message))
         |> Turnstile.refresh()}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:neuro_scavenger, plain(Locale.get_text("Chill")))
         |> Turnstile.refresh()}
    end
  end

  @impl true
  def handle_event("gnome_clicked", _, socket) do
    StatsCounterServer.gnome_captured()

    {:noreply,
     assign(socket, :neuro_scavenger, %{
       name: Locale.get_text("Gnome catched"),
       rarity: "gnome",
       rarity_text: Locale.get_text("gnome")
     })
     |> Turnstile.refresh()}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:neuro_generated, msg}, socket) do
    {:noreply, assign(socket, :neuro_scavenger, plain(msg))}
  end

  @impl true
  def handle_info(:neuro_generation_error, socket) do
    {:noreply, assign(socket, :neuro_scavenger, plain(Locale.get_text("Neuro error")))}
  end

  @impl true
  def handle_info({:queue_place_updated, 0}, socket) do
    {:noreply, assign(socket, :neuro_scavenger, plain(Locale.get_text("Neuro next")))}
  end

  @impl true
  def handle_info({:queue_place_updated, place}, socket) do
    {:noreply,
     assign(socket, :neuro_scavenger, plain(Locale.get_text("Queue place", place: place)))}
  end

  defp plain(name), do: %{name: name, rarity: nil, rarity_text: nil}

  defp format_schedule_message(result) do
    case result do
      :requests_limit_reached -> "Limit reached"
      :scheduled -> "Neuro scheduled"
      :already_scheduled -> "Neuro already scheduled"
    end
    |> Locale.get_text()
  end
end
