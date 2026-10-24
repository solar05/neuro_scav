defmodule NeuroScav.ImageRenderer do
  @moduledoc """
  Draws the share images (SVG to PNG with Resvg) one at a time.

  Resvg's NIF holds a normal scheduler for the whole drawing (tens of
  milliseconds), so several drawings at once held as many schedulers, and
  every page's clicks waited for them. Here at most one is held: the rest
  queue, `@max_queue` at most (past it a request is turned away at once, so
  a burst can't pile up), and one whose caller has given up waiting is
  skipped.
  """

  # ponytail: one drawing at a time; with Resvg's NIF on a dirty scheduler
  # (`schedule = "DirtyCpu"`) they could run side by side again

  use GenServer

  # how long a request waits for its turn and the drawing
  @timeout :timer.seconds(10)
  @max_queue 20

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  The PNG of `svg` drawn with Resvg's `opts`; `{:error, :busy}` when too
  many wait (or the renderer is down), an error when it can't be drawn or
  takes too long.
  """
  @spec png(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def png(svg, opts) do
    with pid when pid != nil <- GenServer.whereis(__MODULE__),
         {:message_queue_len, queued} when queued < @max_queue <-
           Process.info(pid, :message_queue_len) do
      deadline = System.monotonic_time(:millisecond) + @timeout
      GenServer.call(pid, {:png, svg, opts, deadline}, @timeout)
    else
      _full_or_down -> {:error, :busy}
    end
  catch
    :exit, reason -> {:error, reason}
  end

  # ponytail: the fonts load at every drawing; two files, so Resvg's warm
  # `:fontdb` measured no faster (more fonts would make it worth keeping one)
  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call({:png, svg, opts, deadline}, _from, state) do
    if System.monotonic_time(:millisecond) < deadline,
      do: {:reply, draw(svg, opts), state},
      else: {:noreply, state}
  end

  # the PNG as a binary (a list of bytes would be copied in the reply)
  defp draw(svg, opts) do
    Resvg.svg_string_to_png_binary(svg, opts)
  rescue
    error -> {:error, error}
  end
end
