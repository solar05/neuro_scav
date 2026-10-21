defmodule NeuroScavWeb.NeuroScavengerLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NeuroScav.UserRequestsServer

  describe "Index" do
    setup do
      settings = %{schedule_timer: 1, state: [], client: FakeClient}
      GenServer.start_link(UserRequestsServer, settings, name: UserRequestsServer)
      :ok
    end

    test "open neuro_scavengers", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/neuro_scavengers")

      assert html =~ "Здесь будет neuro-дичок"
    end

    test "run request", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/neuro_scavengers")

      assert index_live |> form("#neuro_form") |> render_submit() =~
               "Генерируем..."
    end

    test "when request already scheduled", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/neuro_scavengers")

      assert index_live |> form("#neuro_form") |> render_submit() =~
               "Генерируем..."

      assert index_live |> form("#neuro_form") |> render_submit() =~
               "Генерируем, ожидайте..."
    end

    test "when queue is full", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/neuro_scavengers")

      1..20
      |> Enum.map(fn user ->
        UserRequestsServer.schedule_request("#{user}", "ru")
      end)

      assert index_live |> form("#neuro_form") |> render_submit() =~
               "Достигнут лимит запросов"
    end

    test "share button appears only for a generated neuro name", %{conn: conn} do
      {:ok, index_live, html} = live(conn, ~p"/neuro_scavengers")
      refute html =~ ~s(data-url="/share/)

      send(index_live.pid, {:neuro_generated, "Вася Пупкин"})

      token = Base.url_encode64("Вася Пупкин|neuro", padding: false)
      assert render(index_live) =~ ~s(data-url="/share/#{token}")

      send(index_live.pid, {:queue_place_updated, 2})
      refute render(index_live) =~ ~s(data-url="/share/)
    end

    test "when captcha fails", %{conn: conn} do
      TurnstileMock.set_error(true)
      on_exit(fn -> TurnstileMock.set_error(false) end)

      {:ok, index_live, _html} = live(conn, ~p"/neuro_scavengers")

      assert index_live |> form("#neuro_form") |> render_submit() =~
               "Зачилься"
    end
  end
end
