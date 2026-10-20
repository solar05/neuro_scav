defmodule NeuroScavWeb.Api.HealthController do
  use NeuroScavWeb, :controller

  def health(conn, _params) do
    json(conn, %{result: "Ok"})
  end

  def options(conn, _params), do: send_resp(conn, :no_content, "")
end
