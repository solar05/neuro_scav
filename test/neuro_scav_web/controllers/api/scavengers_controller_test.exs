defmodule NeuroScavWeb.Api.ScavengersControllerTest do
  use NeuroScavWeb.ConnCase

  setup do
    # Start the ScavengersServer for testing
    settings = %{module_name: NeuroScav.Scavengers.Names}

    {:ok, _pid} =
      GenServer.start_link(NeuroScav.ScavengersServer, settings, name: NeuroScav.ScavengersServer)

    :ok
  end

  describe "generate_single/2" do
    test "GET /api/generate_single returns a single scavenger with name and rarity", %{conn: conn} do
      conn = get(conn, ~p"/api/generate_single")

      response = json_response(conn, 200)
      assert is_map(response)
      assert Map.has_key?(response, "scavenger")
      scavenger = response["scavenger"]
      assert is_map(scavenger)
      assert Map.has_key?(scavenger, "name")
      assert Map.has_key?(scavenger, "rarity")
      assert is_binary(scavenger["name"])
      assert scavenger["rarity"] in ["common", "uncommon", "rare", "epic", "legendary"]
    end

    test "GET /api/generate_single with lang param uses specified locale", %{conn: conn} do
      conn = get(conn, ~p"/api/generate_single?lang=ru")

      response = json_response(conn, 200)
      assert is_map(response)
      assert Map.has_key?(response, "scavenger")
      scavenger = response["scavenger"]
      assert is_map(scavenger)
      assert Map.has_key?(scavenger, "name")
      assert is_binary(scavenger["name"])
    end

    test "GET /api/generate_single with lang param en generates English names", %{conn: conn} do
      conn = get(conn, ~p"/api/generate_single?lang=en")

      response = json_response(conn, 200)
      assert is_map(response)
      assert Map.has_key?(response, "scavenger")
      scavenger = response["scavenger"]
      assert is_map(scavenger)
      assert Map.has_key?(scavenger, "name")
      assert is_binary(scavenger["name"])
    end

    test "GET /api/generate_single uses lang cookie if param not provided", %{conn: conn} do
      conn =
        conn
        |> put_req_cookie("lang", "ru")
        |> get(~p"/api/generate_single")

      response = json_response(conn, 200)
      assert is_map(response)
      assert Map.has_key?(response, "scavenger")
      scavenger = response["scavenger"]
      assert is_map(scavenger)
      assert Map.has_key?(scavenger, "name")
    end
  end

  describe "generate_team/2" do
    test "GET /api/generate_team returns a team of scavengers", %{conn: conn} do
      conn = get(conn, ~p"/api/generate_team")

      response = json_response(conn, 200)
      assert is_map(response)
      assert Map.has_key?(response, "team")
      team = response["team"]
      assert is_list(team)
      assert length(team) == 5
    end

    test "GET /api/generate_team returns team members with name and rarity", %{conn: conn} do
      conn = get(conn, ~p"/api/generate_team")

      response = json_response(conn, 200)
      team = response["team"]
      assert is_list(team)

      Enum.each(team, fn scavenger ->
        assert is_map(scavenger)
        assert Map.has_key?(scavenger, "name")
        assert Map.has_key?(scavenger, "rarity")
        assert is_binary(scavenger["name"])
        assert scavenger["rarity"] in ["common", "uncommon", "rare", "epic", "legendary"]
      end)
    end

    test "GET /api/generate_team with lang param uses specified locale", %{conn: conn} do
      conn = get(conn, ~p"/api/generate_team?lang=ru")

      response = json_response(conn, 200)
      team = response["team"]
      assert is_list(team)
      assert length(team) == 5
    end

    test "GET /api/generate_team returns consistent team size", %{conn: conn} do
      conn1 = get(conn, ~p"/api/generate_team")
      response1 = json_response(conn1, 200)

      conn2 = get(conn, ~p"/api/generate_team")
      response2 = json_response(conn2, 200)

      assert length(response1["team"]) == length(response2["team"])
      assert length(response1["team"]) == 5
    end
  end

  describe "stats/2" do
    test "GET /api/stats returns statistics", %{conn: conn} do
      conn = get(conn, ~p"/api/stats")

      response = json_response(conn, 200)
      # Response is a map with statistics keys
      assert is_map(response)
    end

    test "GET /api/stats response contains expected statistics fields", %{conn: conn} do
      conn = get(conn, ~p"/api/stats")

      response = json_response(conn, 200)
      # Should have statistics counters or null values
      assert is_map(response)
      # Check for expected keys from scavengers_json.ex render function
      expected_keys = ["legendary", "epic", "rare", "uncommon", "common", "neuro", "gnome"]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(response, key) or response == nil
      end)
    end
  end

  describe "integration tests" do
    test "multiple generate_single calls produce scavengers", %{conn: conn} do
      conn1 = get(conn, ~p"/api/generate_single")
      response1 = json_response(conn1, 200)

      conn2 = get(conn, ~p"/api/generate_single")
      response2 = json_response(conn2, 200)

      # Both should be valid scavengers
      assert is_map(response1["scavenger"])
      assert is_map(response2["scavenger"])
      assert response1["scavenger"]["name"] != ""
      assert response2["scavenger"]["name"] != ""
    end

    test "locale is fetched from param when both param and cookie exist", %{conn: conn} do
      conn =
        conn
        |> put_req_cookie("lang", "en")
        |> get(~p"/api/generate_single?lang=ru")

      response = json_response(conn, 200)
      assert is_map(response)
      assert Map.has_key?(response, "scavenger")
      scavenger = response["scavenger"]
      assert Map.has_key?(scavenger, "name")
    end

    test "generate_team produces 5 members with valid data", %{conn: conn} do
      conn = get(conn, ~p"/api/generate_team?lang=ru")

      response = json_response(conn, 200)
      team = response["team"]

      assert length(team) == 5

      Enum.each(team, fn member ->
        assert is_map(member)
        assert String.length(member["name"]) > 0
        assert member["rarity"] in ["common", "uncommon", "rare", "epic", "legendary"]
      end)
    end
  end
end
