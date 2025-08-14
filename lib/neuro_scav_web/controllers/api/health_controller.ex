defmodule NeuroScavWeb.Api.HealthController do
  use NeuroScavWeb, :controller

  def health(conn, _params) do
    json(conn, %{result: "Ok"})
  end
end
