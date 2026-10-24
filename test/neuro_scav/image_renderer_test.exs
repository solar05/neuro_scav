defmodule NeuroScav.ImageRendererTest do
  # the renderer is the app's one: a test that holds it can't run beside the share tests
  use ExUnit.Case, async: false

  alias NeuroScav.ImageRenderer

  @svg ~s(<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4"/></svg>)
  @opts [skip_system_fonts: true, resources_dir: System.tmp_dir!()]

  test "draws an SVG to a PNG binary, an error for what isn't one" do
    assert {:ok, <<137, "PNG", _rest::binary>>} = ImageRenderer.png(@svg, @opts)
    assert {:error, _reason} = ImageRenderer.png("not an svg", @opts)
  end

  test "turns a request away at once while too many wait, and skips those given up on" do
    pid = GenServer.whereis(ImageRenderer)
    :sys.suspend(pid)

    try do
      # requests whose callers gave up already (monotonic time may be
      # negative: a deadline is in the past only next to now)
      past = System.monotonic_time(:millisecond) - 1

      for _ <- 1..20,
          do: send(pid, {:"$gen_call", {self(), make_ref()}, {:png, @svg, @opts, past}})

      assert ImageRenderer.png(@svg, @opts) == {:error, :busy}
    after
      :sys.resume(pid)
    end

    # the queue gone through, it draws again
    _ = :sys.get_state(pid)
    assert {:ok, _png} = ImageRenderer.png(@svg, @opts)
    # nothing came back for the skipped ones
    refute_received {_ref, _reply}
  end
end
