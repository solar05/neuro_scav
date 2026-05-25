defmodule NeuroScavWeb.ShareControllerTest do
  use NeuroScavWeb.ConnCase

  @card_themes ~w(void lava swamp arctic storm rust toxic blood abyss nebula)

  defp token_for(name, rarity) do
    Base.url_encode64("#{name}|#{rarity}", padding: false)
  end

  defp expected_theme(name) do
    idx = abs(:erlang.phash2(name)) |> rem(length(@card_themes))
    Enum.at(@card_themes, idx)
  end

  describe "show/2 with a valid token" do
    test "returns 200", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200)
    end

    test "renders the scavenger name", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200) =~ "Alice Adams"
    end

    test "renders the rarity badge", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200) =~ "share-rarity-badge"
    end

    test "renders rarity CSS class on the badge", %{conn: conn} do
      for rarity <- ~w(common uncommon rare epic legendary gnome) do
        conn = get(conn, ~p"/share/#{token_for("Test Name", rarity)}")
        assert html_response(conn, 200) =~ ~s(share-rarity-badge #{rarity})
      end
    end

    test "applies rarity border class to the card", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200) =~ "border-rare"
    end

    test "applies name color class to the name element", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200) =~ "rare-name"
    end

    test "applies a card art theme class derived from the name hash", %{conn: conn} do
      name = "Alice Adams"
      conn = get(conn, ~p"/share/#{token_for(name, "rare")}")
      assert html_response(conn, 200) =~ "theme-#{expected_theme(name)}"
    end

    test "theme is deterministic — same name always gives the same theme", %{conn: conn} do
      name = "Иван Петров"
      token = token_for(name, "legendary")
      html1 = conn |> get(~p"/share/#{token}") |> html_response(200)
      html2 = Phoenix.ConnTest.build_conn() |> get(~p"/share/#{token}") |> html_response(200)
      assert html1 =~ "theme-#{expected_theme(name)}"
      assert html2 =~ "theme-#{expected_theme(name)}"
    end

    test "different names produce different themes across the pool", %{conn: conn} do
      names = ~w(Alice Bob Charlie Diana Eve Frank Grace Henry Iris Jake Karl)

      themes =
        Enum.map(names, fn name ->
          conn = get(conn, ~p"/share/#{token_for(name, "common")}")
          html = html_response(conn, 200)
          Enum.find(@card_themes, fn t -> html =~ "theme-#{t}" end)
        end)

      assert Enum.uniq(themes) |> length() > 1
    end

    test "renders the copy link button", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200) =~ "copy link"
    end

    test "copy link button data-url contains the share path", %{conn: conn} do
      token = token_for("Alice Adams", "rare")
      conn = get(conn, ~p"/share/#{token}")
      assert html_response(conn, 200) =~ ~s(data-url=")
      assert html_response(conn, 200) =~ "/share/#{token}"
    end

    test "renders the try yourself link pointing to root", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      html = html_response(conn, 200)
      assert html =~ "try yourself"
      assert html =~ ~s(href="/")
    end

    test "renders the scavgen branding", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200) =~ "scavgen"
    end

    test "renders OG title meta tag with name and rarity", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      html = html_response(conn, 200)
      assert html =~ ~s(og:title)
      assert html =~ "Alice Adams"
      assert html =~ "rare"
    end

    test "renders OG description meta tag", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200) =~ ~s(og:description)
    end

    test "renders Twitter card meta tag", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      assert html_response(conn, 200) =~ "twitter:card"
    end

    test "works with a Russian name", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Иван Петров", "legendary")}")
      html = html_response(conn, 200)
      assert html =~ "Иван Петров"
      assert html =~ "legendary"
    end

    test "works with all rarity levels", %{conn: conn} do
      for rarity <- ~w(common uncommon rare epic legendary gnome) do
        conn = get(conn, ~p"/share/#{token_for("Test Name", rarity)}")
        assert html_response(conn, 200) =~ rarity
      end
    end

    test "page title includes scavenger name and rarity", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "epic")}")
      html = html_response(conn, 200)
      assert html =~ "<title>"
      assert html =~ "Alice Adams"
      assert html =~ "epic"
    end
  end

  describe "show/2 with an invalid token" do
    test "returns 400 for a completely invalid token", %{conn: conn} do
      conn = get(conn, ~p"/share/not-valid-!!!")
      assert html_response(conn, 400)
    end

    test "returns 400 for a token that decodes without a pipe separator", %{conn: conn} do
      token = Base.url_encode64("JustANameNoPipe", padding: false)
      conn = get(conn, ~p"/share/#{token}")
      assert html_response(conn, 400)
    end

    test "renders the invalid link message", %{conn: conn} do
      token = Base.url_encode64("JustANameNoPipe", padding: false)
      conn = get(conn, ~p"/share/#{token}")
      assert html_response(conn, 400) =~ "invalid link"
    end

    test "renders the go to scavgen link for bad token", %{conn: conn} do
      token = Base.url_encode64("JustANameNoPipe", padding: false)
      conn = get(conn, ~p"/share/#{token}")
      assert html_response(conn, 400) =~ "go to scavgen"
    end

    test "go to scavgen link points to root", %{conn: conn} do
      token = Base.url_encode64("JustANameNoPipe", padding: false)
      conn = get(conn, ~p"/share/#{token}")
      html = html_response(conn, 400)
      assert html =~ "go to scavgen"
      assert html =~ ~s(href="/")
    end

    test "does not render share card body for bad token", %{conn: conn} do
      token = Base.url_encode64("JustANameNoPipe", padding: false)
      conn = get(conn, ~p"/share/#{token}")
      refute html_response(conn, 400) =~ "copy link"
    end
  end
end
