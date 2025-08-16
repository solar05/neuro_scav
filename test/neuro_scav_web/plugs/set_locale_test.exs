defmodule NeuroScavWeb.SetLocaleTest do
  alias NeuroScavWeb.Plugs.SetLocale

  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  @settings [
    store: :cookie,
    key: "_neuro_scav_key",
    signing_salt: "b7zqZIdn",
    same_site: "Lax"
  ]

  describe "set_locale/1" do
    test "sets default locale cookie" do
      conn = prepare_conn()
      assert %{cookies: %{"lang" => "ru"}} = SetLocale.call(conn, SetLocale.init())
    end

    test "fetches cookie, when set" do
      conn = prepare_conn() |> put_resp_cookie("lang", "en")
      assert %{cookies: %{"lang" => "en"}} = SetLocale.call(conn, SetLocale.init())
    end
  end

  defp prepare_conn() do
    conn(:get, "/")
    |> fetch_query_params()
    |> Plug.Session.call(Plug.Session.init(@settings))
    |> fetch_session()
  end
end
