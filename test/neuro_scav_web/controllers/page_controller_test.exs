defmodule NeuroScavWeb.PageControllerTest do
  use NeuroScavWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 302) =~
             "<html><body>You are being <a href=\"/neuro_scavengers\">redirected</a>.</body></html>"
  end
end
