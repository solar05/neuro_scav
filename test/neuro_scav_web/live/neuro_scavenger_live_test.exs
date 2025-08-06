# defmodule NeuroScavWeb.NeuroScavengerLiveTest do
#   use NeuroScavWeb.ConnCase

#   import Phoenix.LiveViewTest
#   import NeuroScav.ScavengersFixtures

#   @create_attrs %{name: "some name"}
#   @update_attrs %{name: "some updated name"}
#   @invalid_attrs %{name: nil}

#   defp create_neuro_scavenger(_) do
#     neuro_scavenger = neuro_scavenger_fixture()
#     %{neuro_scavenger: neuro_scavenger}
#   end

#   describe "Index" do
#     setup [:create_neuro_scavenger]

    # test "lists all neuro_scavengers", %{conn: conn, neuro_scavenger: neuro_scavenger} do
    #   {:ok, _index_live, html} = live(conn, ~p"/neuro_scavengers")

    #   assert html =~ "Listing Neuro scavengers"
    #   assert html =~ neuro_scavenger.name
    # end

    # test "saves new neuro_scavenger", %{conn: conn} do
    #   {:ok, index_live, _html} = live(conn, ~p"/neuro_scavengers")

    #   assert index_live |> element("a", "New Neuro scavenger") |> render_click() =~
    #            "New Neuro scavenger"

    #   assert_patch(index_live, ~p"/neuro_scavengers/new")

    #   assert index_live
    #          |> form("#neuro_scavenger-form", neuro_scavenger: @invalid_attrs)
    #          |> render_change() =~ "can&#39;t be blank"

    #   assert index_live
    #          |> form("#neuro_scavenger-form", neuro_scavenger: @create_attrs)
    #          |> render_submit()

    #   assert_patch(index_live, ~p"/neuro_scavengers")

    #   html = render(index_live)
    #   assert html =~ "Neuro scavenger created successfully"
    #   assert html =~ "some name"
    # end

    # test "updates neuro_scavenger in listing", %{conn: conn, neuro_scavenger: neuro_scavenger} do
    #   {:ok, index_live, _html} = live(conn, ~p"/neuro_scavengers")

    #   assert index_live
    #          |> element("#neuro_scavengers-#{neuro_scavenger.id} a", "Edit")
    #          |> render_click() =~
    #            "Edit Neuro scavenger"

    #   assert_patch(index_live, ~p"/neuro_scavengers/#{neuro_scavenger}/edit")

    #   assert index_live
    #          |> form("#neuro_scavenger-form", neuro_scavenger: @invalid_attrs)
    #          |> render_change() =~ "can&#39;t be blank"

    #   assert index_live
    #          |> form("#neuro_scavenger-form", neuro_scavenger: @update_attrs)
    #          |> render_submit()

    #   assert_patch(index_live, ~p"/neuro_scavengers")

    #   html = render(index_live)
    #   assert html =~ "Neuro scavenger updated successfully"
    #   assert html =~ "some updated name"
    # end

    # test "deletes neuro_scavenger in listing", %{conn: conn, neuro_scavenger: neuro_scavenger} do
    #   {:ok, index_live, _html} = live(conn, ~p"/neuro_scavengers")

    #   assert index_live
    #          |> element("#neuro_scavengers-#{neuro_scavenger.id} a", "Delete")
    #          |> render_click()

    #   refute has_element?(index_live, "#neuro_scavengers-#{neuro_scavenger.id}")
    # end
  # end

  # describe "Show" do
    # setup [:create_neuro_scavenger]

    # test "displays neuro_scavenger", %{conn: conn, neuro_scavenger: neuro_scavenger} do
    #   {:ok, _show_live, html} = live(conn, ~p"/neuro_scavengers/#{neuro_scavenger}")

    #   assert html =~ "Show Neuro scavenger"
    #   assert html =~ neuro_scavenger.name
    # end

    # test "updates neuro_scavenger within modal", %{conn: conn, neuro_scavenger: neuro_scavenger} do
    #   {:ok, show_live, _html} = live(conn, ~p"/neuro_scavengers/#{neuro_scavenger}")

    #   assert show_live |> element("a", "Edit") |> render_click() =~
    #            "Edit Neuro scavenger"

    #   assert_patch(show_live, ~p"/neuro_scavengers/#{neuro_scavenger}/show/edit")

    #   assert show_live
    #          |> form("#neuro_scavenger-form", neuro_scavenger: @invalid_attrs)
    #          |> render_change() =~ "can&#39;t be blank"

    #   assert show_live
    #          |> form("#neuro_scavenger-form", neuro_scavenger: @update_attrs)
    #          |> render_submit()

    #   assert_patch(show_live, ~p"/neuro_scavengers/#{neuro_scavenger}")

    #   html = render(show_live)
    #   assert html =~ "Neuro scavenger updated successfully"
    #   assert html =~ "some updated name"
    # end
#   end
# end
