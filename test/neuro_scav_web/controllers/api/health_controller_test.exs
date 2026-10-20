defmodule NeuroScavWeb.HealthControllerTest do
  use NeuroScavWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/api/health")

    assert json_response(conn, 200)
  end

  describe "cors" do
    setup do
      Application.put_env(:neuro_scav, :cors_origins, ["https://allowed.example"])
      on_exit(fn -> Application.delete_env(:neuro_scav, :cors_origins) end)
    end

    test "allows configured origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://allowed.example")
        |> get(~p"/api/health")

      assert get_resp_header(conn, "access-control-allow-origin") == ["https://allowed.example"]
    end

    test "rejects unknown origin", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://evil.example")
        |> get(~p"/api/health")

      assert get_resp_header(conn, "access-control-allow-origin") == []
    end

    test "answers preflight", %{conn: conn} do
      conn =
        conn
        |> put_req_header("origin", "https://allowed.example")
        |> put_req_header("access-control-request-method", "POST")
        |> options(~p"/api/generate_single")

      assert conn.status == 204
      assert get_resp_header(conn, "access-control-allow-origin") == ["https://allowed.example"]
    end
  end
end
