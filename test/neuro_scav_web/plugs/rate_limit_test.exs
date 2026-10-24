defmodule NeuroScavWeb.RateLimitTest do
  alias NeuroScavWeb.Plugs.RateLimit

  use ExUnit.Case, async: true
  import Plug.Test

  test "lets the limit through, then answers 429 for the rest of the window" do
    # an address of its own: the counts are the app's
    ip = {10, 0, 0, rem(System.unique_integer([:positive]), 250)}
    opts = RateLimit.init(limit: 2, window_ms: 60_000)

    request = fn ->
      conn(:get, "/api/health") |> Map.put(:remote_ip, ip) |> RateLimit.call(opts)
    end

    refute request.().halted
    refute request.().halted

    denied = request.()
    assert denied.halted and denied.status == 429
  end
end
