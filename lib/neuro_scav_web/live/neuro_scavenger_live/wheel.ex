defmodule NeuroScavWeb.NeuroScavengerLive.Wheel do
  use NeuroScavWeb, :live_view
  use NeuroScavWeb.GnomeCapture

  alias NeuroScav.Locale

  # priv/static/sounds/wheel_spin.mp3 must be at least @max_spin_ms long;
  # shorter spins cut it with a fade when the winner modal mounts
  @min_spin_ms 6_000
  @max_spin_ms 20_000
  @spin_ms_per_entry 2_000
  @ms_per_turn 1_200
  @max_entries 100
  @max_entry_length 40
  @max_label_length 16

  @impl true
  def mount(_params, session, socket) do
    locale = Map.get(session, "lang")
    if connected?(socket), do: Locale.setup_locale(locale)

    {:ok,
     assign(socket,
       entries: [
         gettext("Wheel default 1"),
         gettext("Wheel default 2"),
         gettext("Wheel default 3")
       ],
       rotation: 0,
       spinning: false,
       pending: nil,
       winner: nil,
       max_entries: @max_entries,
       spin_ms: @min_spin_ms
     )}
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{spinning: true}} = socket)
      when event in ["update_entries", "spin"],
      do: {:noreply, socket}

  def handle_event("update_entries", %{"entries" => text}, socket),
    do: {:noreply, assign(socket, :entries, parse_entries(text))}

  def handle_event("spin", _params, %{assigns: %{entries: []}} = socket), do: {:noreply, socket}

  def handle_event("spin", _params, %{assigns: %{entries: entries, rotation: rotation}} = socket) do
    count = length(entries)
    index = Enum.random(0..(count - 1))
    spin_ms = spin_ms(count)
    turns = div(spin_ms, @ms_per_turn)
    Process.send_after(self(), :reveal, spin_ms)

    {:noreply,
     assign(socket,
       spinning: true,
       pending: index,
       winner: nil,
       spin_ms: spin_ms,
       rotation: target_rotation(rotation, index, count, 0.1 + :rand.uniform() * 0.8, turns)
     )}
  end

  def handle_event("remove_winner", _params, %{assigns: %{winner: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("remove_winner", _params, %{assigns: %{pending: pending}} = socket) do
    {:noreply, socket |> update(:entries, &List.delete_at(&1, pending)) |> assign(:winner, nil)}
  end

  def handle_event("close_winner", _params, socket), do: {:noreply, assign(socket, :winner, nil)}

  @impl true
  def handle_info(:reveal, %{assigns: %{entries: entries, pending: pending}} = socket) do
    {:noreply, assign(socket, spinning: false, winner: Enum.at(entries, pending))}
  end

  @doc "Spin length: 2 entries spin 6s, each extra entry adds 2s, capped at 20s (9+ entries)."
  def spin_ms(count),
    do:
      (@min_spin_ms + (count - 2) * @spin_ms_per_entry) |> max(@min_spin_ms) |> min(@max_spin_ms)

  @doc """
  New clockwise rotation (degrees) that stops the top pointer inside segment
  `index` of `count` after `turns` full turns; `offset` (0..1) is the landing
  point within the segment. Rotation only grows, so the CSS transition always
  spins forward.
  """
  def target_rotation(current, index, count, offset, turns) do
    angle = (index + offset) * 360 / count
    current + turns * 360 + pos_mod(360 - angle - pos_mod(current, 360), 360)
  end

  defp pos_mod(x, m), do: x - m * Float.floor(x / m)

  defp parse_entries(text) do
    text
    |> String.split("\n")
    |> Enum.map(&(&1 |> String.trim() |> String.slice(0, @max_entry_length)))
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(@max_entries)
  end

  # Segments go clockwise from 12 o'clock in a 200x200 viewBox.
  defp segments([]), do: []

  defp segments(entries) do
    count = length(entries)
    step = 360 / count
    font_size = min(10, 300 / count)

    entries
    |> Enum.with_index()
    |> Enum.map(fn {label, i} ->
      {fill, text} = segment_colors(i, count)

      %{
        label: truncate(label),
        path: sector_path(i * step, (i + 1) * step),
        rotate: (i + 0.5) * step - 90,
        fill: fill,
        text: text,
        font_size: font_size
      }
    end)
  end

  # odd count: the last segment gets a third color so it doesn't match the first
  defp segment_colors(i, count) when rem(count, 2) == 1 and count > 1 and i == count - 1,
    do: {"#7e7f8b", "#fff"}

  defp segment_colors(i, _count) when rem(i, 2) == 0, do: {"#d49300", "#212529"}
  defp segment_colors(_i, _count), do: {"#3a3a46", "#fff"}

  defp sector_path(from, to) when to - from >= 360,
    do: "M 100 2 A 98 98 0 1 1 100 198 A 98 98 0 1 1 100 2 Z"

  defp sector_path(from, to) do
    {x1, y1} = rim_point(from)
    {x2, y2} = rim_point(to)
    large_arc = if to - from > 180, do: 1, else: 0
    "M 100 100 L #{x1} #{y1} A 98 98 0 #{large_arc} 1 #{x2} #{y2} Z"
  end

  defp rim_point(deg) do
    rad = deg * :math.pi() / 180
    {Float.round(100 + 98 * :math.sin(rad), 2), Float.round(100 - 98 * :math.cos(rad), 2)}
  end

  defp truncate(label) do
    if String.length(label) > @max_label_length,
      do: String.slice(label, 0, @max_label_length - 1) <> "…",
      else: label
  end
end
