defmodule NeuroScavWeb.SetUserIdTest do
  alias NeuroScavWeb.Plugs.SetUserId

  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  @settings [
    store: :cookie,
    key: "_neuro_scav_key",
    signing_salt: "b7zqZIdn",
    same_site: "Lax"
  ]

  describe "set_user_id/1" do
    test "sets user_id" do
      conn = prepare_conn()

      assert %{private: %{plug_session: %{"user_id" => _}}} =
               SetUserId.call(conn, SetUserId.init())
    end

    test "when id is set, do nothing" do
      user_id = Uniq.UUID.uuid4()
      conn = prepare_conn() |> put_session("user_id", user_id)

      assert %{private: %{plug_session: %{"user_id" => ^user_id}}} =
               SetUserId.call(conn, SetUserId.init())
    end
  end

  defp prepare_conn() do
    conn(:get, "/")
    |> fetch_query_params()
    |> Plug.Session.call(Plug.Session.init(@settings))
    |> fetch_session()
  end
end
