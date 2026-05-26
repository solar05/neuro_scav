defmodule NeuroScavWeb.NeuroScavengerLive.Neuro do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.{Locale, PubSub}

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
      |> assign(:neuro_scavenger, scav(Locale.get_text("Neuro placeholder"), nil))
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

        {message, rarity} = format_schedule_message(result)

        {:noreply,
         socket
         |> assign(:neuro_scavenger, scav(message, rarity))
         |> Turnstile.refresh()}

      {:error, _error} ->
        {:noreply,
         socket
         |> assign(:neuro_scavenger, scav(Locale.get_text("Chill"), "error"))
         |> Turnstile.refresh()}
    end
  end

  def on_gnome_clicked(socket) do
    {:noreply,
     socket
     |> assign(:neuro_scavenger, scav(Locale.get_text("Gnome catched"), "gnome"))
     |> Turnstile.refresh()}
  end

  # pubsub callbacks
  @impl true
  def handle_info({:neuro_generated, msg}, socket) do
    {:noreply, assign(socket, :neuro_scavenger, scav(msg, "neuro"))}
  end

  @impl true
  def handle_info(:neuro_generation_error, socket) do
    {:noreply, assign(socket, :neuro_scavenger, scav(Locale.get_text("Neuro error"), "error"))}
  end

  @impl true
  def handle_info({:queue_place_updated, 0}, socket) do
    {:noreply, assign(socket, :neuro_scavenger, scav(Locale.get_text("Neuro next"), "queue"))}
  end

  @impl true
  def handle_info({:queue_place_updated, place}, socket) do
    {:noreply,
     assign(
       socket,
       :neuro_scavenger,
       scav(Locale.get_text("Queue place", place: place), "queue")
     )}
  end

  defp scav(name, rarity), do: %{name: name, rarity: rarity}

  defp format_schedule_message(:requests_limit_reached),
    do: {Locale.get_text("Limit reached"), "error"}

  defp format_schedule_message(:scheduled),
    do: {Locale.get_text("Neuro scheduled"), "queue"}

  defp format_schedule_message(:already_scheduled),
    do: {Locale.get_text("Neuro already scheduled"), "queue"}
end
