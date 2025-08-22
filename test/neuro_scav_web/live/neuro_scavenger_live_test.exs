defmodule NeuroScavWeb.NeuroScavengerLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NeuroScav.UserRequestsServer

  describe "Index" do
    setup do
      settings = %{schedule_timer: 1, state: [], client: FakeClient}
      {:ok, _pid} = GenServer.start_link(UserRequestsServer, settings, name: UserRequestsServer)
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
  end
end
