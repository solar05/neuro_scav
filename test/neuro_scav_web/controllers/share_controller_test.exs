defmodule NeuroScavWeb.ShareControllerTest do
  use NeuroScavWeb.ConnCase

  @card_themes ~w(void lava swamp arctic storm rust toxic blood abyss nebula)

  @theme_bg1 %{
    "void" => "#0d0d2e",
    "lava" => "#3a0800",
    "swamp" => "#0d2210",
    "arctic" => "#0a1e2e",
    "storm" => "#060615",
    "rust" => "#1a0f08",
    "toxic" => "#0e1400",
    "blood" => "#100202",
    "abyss" => "#001820",
    "nebula" => "#130820"
  }

  @rarity_border_colors %{
    "legendary" => "#ff8c00",
    "epic" => "#9932cc",
    "rare" => "#1e90ff",
    "uncommon" => "#22aa44",
    "common" => "#888888",
    "gnome" => "#ff44bb"
  }

  @rarity_badge_colors %{
    "legendary" => "#ff8c00",
    "epic" => "#9932cc",
    "rare" => "#1e90ff",
    "uncommon" => "#22aa44",
    "common" => "#888888",
    "gnome" => "#ff44bb"
  }

  @gnome_rainbow_colors ~w(#ff6b6b #ffaa33 #ffe044 #44ee88 #44aaff #bb55ff #ff44bb)

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

    test "renders og:image meta tag pointing to image endpoint", %{conn: conn} do
      token = token_for("Alice Adams", "rare")
      conn = get(conn, ~p"/share/#{token}")
      assert html_response(conn, 200) =~ ~s(og:image)
    end

    test "og:image URL contains the share token and /image path", %{conn: conn} do
      token = token_for("Alice Adams", "rare")
      conn = get(conn, ~p"/share/#{token}")
      html = html_response(conn, 200)
      assert html =~ "/share/#{token}/image"
    end

    test "renders og:image:width as 1200 and og:image:height as 630", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      html = html_response(conn, 200)
      assert html =~ ~s(og:image:width)
      assert html =~ ~s(content="1200")
      assert html =~ ~s(og:image:height)
      assert html =~ ~s(content="630")
    end

    test "renders twitter:image meta tag", %{conn: conn} do
      token = token_for("Alice Adams", "rare")
      conn = get(conn, ~p"/share/#{token}")
      html = html_response(conn, 200)
      assert html =~ "twitter:image"
      assert html =~ "/share/#{token}/image"
    end

    test "twitter:card is summary_large_image", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}")
      html = html_response(conn, 200)
      assert html =~ "twitter:card"
      assert html =~ "summary_large_image"
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

  describe "og_image/2 with a valid token" do
    test "returns 200", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert response(conn, 200)
    end

    test "content-type is image/svg+xml", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert ["image/svg+xml" <> _] = get_resp_header(conn, "content-type")
    end

    test "sets public cache-control header", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert ["public, max-age=86400"] = get_resp_header(conn, "cache-control")
    end

    test "returns valid SVG with correct dimensions", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      body = response(conn, 200)
      assert body =~ ~s(<svg xmlns="http://www.w3.org/2000/svg")
      assert body =~ ~s(width="1200")
      assert body =~ ~s(height="630")
    end

    test "SVG contains the scavenger name", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      body = response(conn, 200)
      # Name is split into tspan elements per word in the new card design
      assert body =~ "Alice"
      assert body =~ "Adams"
    end

    test "SVG contains the rarity text", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      # Badge shows uppercase rarity in the new card design
      assert response(conn, 200) =~ "RARE"
    end

    test "SVG uses rarity-specific border color", %{conn: conn} do
      for {rarity, color} <- @rarity_border_colors do
        conn = get(conn, ~p"/share/#{token_for("Test Name", rarity)}/image")

        assert response(conn, 200) =~ ~s(stroke="#{color}"),
               "expected stroke #{color} for rarity #{rarity}"
      end
    end

    test "SVG uses rarity-specific badge color", %{conn: conn} do
      for {rarity, color} <- @rarity_badge_colors do
        conn = get(conn, ~p"/share/#{token_for("Test Name", rarity)}/image")

        assert response(conn, 200) =~ ~s(fill="#{color}"),
               "expected fill #{color} for rarity #{rarity}"
      end
    end

    test "rare rarity uses border color for both stroke and badge text", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Test Name", "rare")}/image")
      body = response(conn, 200)
      assert body =~ ~s(stroke="#1e90ff")
      assert body =~ ~s(fill="#1e90ff")
    end

    test "theme is deterministic — same name always produces the same SVG", %{conn: conn} do
      token = token_for("Иван Петров", "legendary")
      svg1 = conn |> get(~p"/share/#{token}/image") |> response(200)
      svg2 = Phoenix.ConnTest.build_conn() |> get(~p"/share/#{token}/image") |> response(200)
      assert svg1 == svg2
    end

    test "SVG art background matches expected theme for the given name", %{conn: conn} do
      name = "Alice Adams"
      theme = expected_theme(name)
      expected_bg1 = Map.fetch!(@theme_bg1, theme)

      conn = get(conn, ~p"/share/#{token_for(name, "rare")}/image")
      assert response(conn, 200) =~ expected_bg1
    end

    test "different names with different themes produce different art backgrounds", %{conn: conn} do
      names = ~w(Alice Bob Charlie Diana Eve Frank Grace Henry Iris Jake Karl)

      svgs =
        Enum.map(names, fn name ->
          conn |> get(~p"/share/#{token_for(name, "common")}/image") |> response(200)
        end)

      unique_svgs = Enum.uniq(svgs)
      assert length(unique_svgs) > 1
    end

    test "ampersand in name is XML-escaped", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice & Bob", "common")}/image")
      body = response(conn, 200)
      assert body =~ "&amp;"
      refute body =~ " & "
    end

    test "angle brackets in name are XML-escaped", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("<script>", "common")}/image")
      body = response(conn, 200)
      assert body =~ "&lt;"
      refute body =~ "<script>"
    end

    test "short name uses larger font than long name", %{conn: conn} do
      short_conn = get(conn, ~p"/share/#{token_for("Al Bo", "common")}/image")

      long_conn =
        get(conn, ~p"/share/#{token_for("Bartholomew Konstantinopolsky", "common")}/image")

      short_font = extract_name_font_size(response(short_conn, 200))
      long_font = extract_name_font_size(response(long_conn, 200))

      assert short_font > long_font
    end

    test "SVG contains scavgen branding", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert response(conn, 200) =~ "SCAVGEN"
    end

    test "works with Russian name", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Иван Петров", "legendary")}/image")
      body = response(conn, 200)
      assert body =~ "Иван"
      assert body =~ "Петров"
      assert body =~ "LEGENDARY"
    end

    test "works with all rarity levels", %{conn: conn} do
      for rarity <- ~w(common uncommon rare epic legendary gnome) do
        conn = get(conn, ~p"/share/#{token_for("Test Name", rarity)}/image")
        assert response(conn, 200) =~ String.upcase(rarity)
      end
    end
  end

  describe "og_image/2 gnome rarity" do
    test "badge label is GNOME", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Gnome Captured", "gnome")}/image")
      assert response(conn, 200) =~ "GNOME"
    end

    test "border color is gnome pink", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Gnome Captured", "gnome")}/image")
      assert response(conn, 200) =~ ~s(stroke="#ff44bb")
    end

    test "name text uses gnome gold color", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Gnome Captured", "gnome")}/image")
      assert response(conn, 200) =~ ~s(fill="#ffe044")
    end

    test "SVG contains all rainbow diamond colors", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Gnome Captured", "gnome")}/image")
      body = response(conn, 200)

      for color <- @gnome_rainbow_colors do
        assert body =~ color, "expected rainbow color #{color} in gnome SVG"
      end
    end

    test "gnome has more decoration polygons than legendary", %{conn: conn} do
      gnome_svg =
        conn |> get(~p"/share/#{token_for("Test Name", "gnome")}/image") |> response(200)

      legendary_svg =
        conn |> get(~p"/share/#{token_for("Test Name", "legendary")}/image") |> response(200)

      gnome_polygons = gnome_svg |> String.split("<polygon") |> length()
      legendary_polygons = legendary_svg |> String.split("<polygon") |> length()

      assert gnome_polygons > legendary_polygons
    end
  end

  describe "og_image/2 with an invalid token" do
    test "returns 200 (always serves an image)", %{conn: conn} do
      conn = get(conn, ~p"/share/not-valid-token/image")
      assert response(conn, 200)
    end

    test "content-type is image/svg+xml", %{conn: conn} do
      conn = get(conn, ~p"/share/not-valid-token/image")
      assert ["image/svg+xml" <> _] = get_resp_header(conn, "content-type")
    end

    test "returns valid SVG", %{conn: conn} do
      conn = get(conn, ~p"/share/not-valid-token/image")
      assert response(conn, 200) =~ ~s(<svg xmlns="http://www.w3.org/2000/svg")
    end

    test "SVG for token with no pipe separator is also valid", %{conn: conn} do
      token = Base.url_encode64("JustANameNoPipe", padding: false)
      conn = get(conn, ~p"/share/#{token}/image")
      body = response(conn, 200)
      assert body =~ ~s(<svg)
      assert body =~ ~s(width="1200")
    end
  end

  defp extract_name_font_size(svg) do
    case Regex.run(~r/font-size="(\d+)"/, svg) do
      [_, size] -> String.to_integer(size)
      _ -> 0
    end
  end
end
