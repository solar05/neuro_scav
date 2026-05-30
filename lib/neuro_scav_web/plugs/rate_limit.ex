defmodule NeuroScavWeb.Plugs.RateLimit do
  @moduledoc """
  Rate limiting plug using Hammer.

  Limits API requests based on IP address or session user ID.
  Default: 200 requests per 1 minute window.
  """

  import Plug.Conn

  def init(options) do
    %{
      limit: Keyword.get(options, :limit, 60),
      window_ms: Keyword.get(options, :window_ms, 60_000)
    }
  end

  def call(conn, %{limit: limit, window_ms: window_ms}) do
    ip = get_client_ip(conn)
    key = "rate_limit:#{ip}"

    case Hammer.check_rate(key, window_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_status(429)
        |> Phoenix.Controller.json(%{
          error: "Too many requests",
          status: 429,
          message:
            "Rate limit exceeded. Maximum #{limit} requests per #{div(window_ms, 1000)} seconds."
        })
        |> halt()
    end
  end

  defp get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
    end
  end
end
