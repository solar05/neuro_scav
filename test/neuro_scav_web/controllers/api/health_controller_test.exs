defmodule NeuroScavWeb.HealthControllerTest do
  use NeuroScavWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/api/health")

    assert json_response(conn, 200)
  end
end
