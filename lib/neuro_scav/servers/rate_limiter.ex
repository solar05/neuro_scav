defmodule NeuroScav.RateLimiter do
  @moduledoc """
  Request counts for `NeuroScavWeb.Plugs.RateLimit`, in ETS (Hammer): a
  fixed window per key, the stale ones swept every minute.
  """

  use Hammer, backend: :ets
end
