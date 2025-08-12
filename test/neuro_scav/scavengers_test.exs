# defmodule NeuroScav.ScavengersTest do
#   use NeuroScav.DataCase

#   alias NeuroScav.Scavengers

#   describe "neuro_scavengers" do
#     alias NeuroScav.Scavengers.NeuroScavenger

#     import NeuroScav.ScavengersFixtures

#     @invalid_attrs %{name: nil}

#     test "list_neuro_scavengers/0 returns all neuro_scavengers" do
#       neuro_scavenger = neuro_scavenger_fixture()
#       assert Scavengers.list_neuro_scavengers() == [neuro_scavenger]
#     end

#     test "get_neuro_scavenger!/1 returns the neuro_scavenger with given id" do
#       neuro_scavenger = neuro_scavenger_fixture()
#       assert Scavengers.get_neuro_scavenger!(neuro_scavenger.id) == neuro_scavenger
#     end

#     test "create_neuro_scavenger/1 with valid data creates a neuro_scavenger" do
#       valid_attrs = %{name: "some name"}

#       assert {:ok, %NeuroScavenger{} = neuro_scavenger} =
#                Scavengers.create_neuro_scavenger(valid_attrs)

#       assert neuro_scavenger.name == "some name"
#     end

#     test "create_neuro_scavenger/1 with invalid data returns error changeset" do
#       assert {:error, %Ecto.Changeset{}} = Scavengers.create_neuro_scavenger(@invalid_attrs)
#     end

#     test "update_neuro_scavenger/2 with valid data updates the neuro_scavenger" do
#       neuro_scavenger = neuro_scavenger_fixture()
#       update_attrs = %{name: "some updated name"}

#       assert {:ok, %NeuroScavenger{} = neuro_scavenger} =
#                Scavengers.update_neuro_scavenger(neuro_scavenger, update_attrs)

#       assert neuro_scavenger.name == "some updated name"
#     end

#     test "update_neuro_scavenger/2 with invalid data returns error changeset" do
#       neuro_scavenger = neuro_scavenger_fixture()

#       assert {:error, %Ecto.Changeset{}} =
#                Scavengers.update_neuro_scavenger(neuro_scavenger, @invalid_attrs)

#       assert neuro_scavenger == Scavengers.get_neuro_scavenger!(neuro_scavenger.id)
#     end

#     test "delete_neuro_scavenger/1 deletes the neuro_scavenger" do
#       neuro_scavenger = neuro_scavenger_fixture()
#       assert {:ok, %NeuroScavenger{}} = Scavengers.delete_neuro_scavenger(neuro_scavenger)

#       assert_raise Ecto.NoResultsError, fn ->
#         Scavengers.get_neuro_scavenger!(neuro_scavenger.id)
#       end
#     end

#     test "change_neuro_scavenger/1 returns a neuro_scavenger changeset" do
#       neuro_scavenger = neuro_scavenger_fixture()
#       assert %Ecto.Changeset{} = Scavengers.change_neuro_scavenger(neuro_scavenger)
#     end
#   end
# end
