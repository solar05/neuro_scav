defmodule NeuroScavWeb.ShareControllerTest do
  use NeuroScavWeb.ConnCase

  alias NeuroScav.Raid.Report

  @locations NeuroScav.Raid.locations()

  defp token_for(name, rarity) do
    Base.url_encode64("#{name}|#{rarity}", padding: false)
  end

  defp expected_location(name) do
    Enum.at(@locations, :erlang.phash2(name, length(@locations)))
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
      for rarity <- ~w(common uncommon rare epic legendary gnome neuro) do
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

    test "lies on the region's map, the card showing a location by the name's hash", %{
      conn: conn
    } do
      name = "Alice Adams"
      html = conn |> get(~p"/share/#{token_for(name, "rare")}") |> html_response(200)
      location = expected_location(name)

      assert html =~ "share-map-page raid-location-#{location}"
      assert html =~ "share-art-#{location}" and html =~ "Норвинская область"
    end

    test "location is deterministic — same name always gives the same one", %{conn: conn} do
      name = "Иван Петров"
      token = token_for(name, "legendary")
      html1 = conn |> get(~p"/share/#{token}") |> html_response(200)
      html2 = Phoenix.ConnTest.build_conn() |> get(~p"/share/#{token}") |> html_response(200)
      assert html1 =~ "share-art-#{expected_location(name)}"
      assert html2 =~ "share-art-#{expected_location(name)}"
    end

    test "different names produce different locations across the pool", %{conn: conn} do
      names = ~w(Alice Bob Charlie Diana Eve Frank Grace Henry Iris Jake Karl)

      locations =
        Enum.map(names, fn name ->
          conn = get(conn, ~p"/share/#{token_for(name, "common")}")
          html = html_response(conn, 200)
          Enum.find(@locations, fn location -> html =~ "share-art-#{location}" end)
        end)

      assert Enum.uniq(locations) |> length() > 1
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
      for rarity <- ~w(common uncommon rare epic legendary gnome neuro) do
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

    test "rejects a rarity the site doesn't have and what isn't text", %{conn: conn} do
      for token <- [
            token_for("Alice Adams", "mythic"),
            Base.url_encode64(<<0xFF, 0xFE, "|rare">>, padding: false)
          ] do
        assert conn |> get(~p"/share/#{token}") |> html_response(400) =~ "invalid link"
      end
    end

    test "cuts a name past 40 characters short, so its card stays cheap to draw", %{conn: conn} do
      name = String.duplicate("А", 30) <> " " <> String.duplicate("Б", 70)
      html = conn |> get(~p"/share/#{token_for(name, "rare")}") |> html_response(200)

      assert html =~ String.duplicate("Б", 9)
      refute html =~ String.duplicate("Б", 10)
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

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  defp valid_png?(binary), do: binary_part(binary, 0, 8) == @png_signature

  describe "og_image/2 with a valid token" do
    test "returns 200", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert response(conn, 200)
    end

    test "content-type is image/png", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert ["image/png" <> _] = get_resp_header(conn, "content-type")
    end

    test "sets public cache-control header", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert ["public, max-age=86400"] = get_resp_header(conn, "cache-control")
    end

    test "returns a valid PNG image", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert valid_png?(response(conn, 200))
    end

    test "PNG is non-trivial (larger than a blank image)", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Alice Adams", "rare")}/image")
      assert byte_size(response(conn, 200)) > 10_000
    end

    test "PNG output is deterministic — same name always produces the same image", %{conn: conn} do
      token = token_for("Иван Петров", "legendary")
      png1 = conn |> get(~p"/share/#{token}/image") |> response(200)
      png2 = Phoenix.ConnTest.build_conn() |> get(~p"/share/#{token}/image") |> response(200)
      assert png1 == png2
    end

    test "different names produce different PNG images", %{conn: conn} do
      names = ~w(Alice Bob Charlie Diana Eve Frank Grace Henry Iris Jake Karl)

      pngs =
        Enum.map(names, fn name ->
          conn |> get(~p"/share/#{token_for(name, "common")}/image") |> response(200)
        end)

      assert Enum.uniq(pngs) |> length() > 1
    end

    test "different rarities for the same name produce different PNG images", %{conn: conn} do
      pngs =
        for rarity <- ~w(common uncommon rare epic legendary gnome neuro) do
          conn |> get(~p"/share/#{token_for("Test Name", rarity)}/image") |> response(200)
        end

      assert Enum.uniq(pngs) |> length() > 1
    end

    test "names with special characters produce valid PNG", %{conn: conn} do
      for name <- ["Alice & Bob", "<script>alert(1)</script>", "O'Brien"] do
        conn = get(conn, ~p"/share/#{token_for(name, "common")}/image")
        assert valid_png?(response(conn, 200)), "expected valid PNG for name: #{name}"
      end
    end

    test "works with Russian name", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Иван Петров", "legendary")}/image")
      assert valid_png?(response(conn, 200))
    end

    test "works with all rarity levels", %{conn: conn} do
      for rarity <- ~w(common uncommon rare epic legendary gnome neuro) do
        conn = get(conn, ~p"/share/#{token_for("Test Name", rarity)}/image")
        assert valid_png?(response(conn, 200)), "expected valid PNG for rarity: #{rarity}"
      end
    end
  end

  describe "og_image/2 gnome rarity" do
    test "returns valid PNG", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Gnome Captured", "gnome")}/image")
      assert valid_png?(response(conn, 200))
    end

    test "gnome PNG differs from legendary PNG for the same name", %{conn: conn} do
      gnome_png =
        conn |> get(~p"/share/#{token_for("Test Name", "gnome")}/image") |> response(200)

      legendary_png =
        conn |> get(~p"/share/#{token_for("Test Name", "legendary")}/image") |> response(200)

      assert gnome_png != legendary_png
    end

    test "gnome PNG is non-trivial", %{conn: conn} do
      conn = get(conn, ~p"/share/#{token_for("Gnome Captured", "gnome")}/image")
      assert byte_size(response(conn, 200)) > 10_000
    end
  end

  describe "og_image/2 with an invalid token" do
    test "returns 200 (always serves an image)", %{conn: conn} do
      conn = get(conn, ~p"/share/not-valid-token/image")
      assert response(conn, 200)
    end

    test "content-type is image/png", %{conn: conn} do
      conn = get(conn, ~p"/share/not-valid-token/image")
      assert ["image/png" <> _] = get_resp_header(conn, "content-type")
    end

    test "returns a valid PNG image", %{conn: conn} do
      conn = get(conn, ~p"/share/not-valid-token/image")
      assert valid_png?(response(conn, 200))
    end

    test "token with no pipe separator also returns a valid PNG", %{conn: conn} do
      token = Base.url_encode64("JustANameNoPipe", padding: false)
      conn = get(conn, ~p"/share/#{token}/image")
      assert valid_png?(response(conn, 200))
    end
  end

  describe "team share" do
    defp team_token(members) do
      members
      |> Enum.map_join("\n", fn {name, rarity} -> "#{name}|#{rarity}" end)
      |> Base.url_encode64(padding: false)
    end

    @team [{"Алиса Аврора", "rare"}, {"Дед Мороз", "legendary"}, {"Вася Пупкин", "common"}]

    test "lists every member with its rarity", %{conn: conn} do
      html = conn |> get(~p"/share/team/#{team_token(@team)}") |> html_response(200)

      for {name, rarity} <- @team do
        assert html =~ name
        assert html =~ rarity
      end
    end

    test "titles the card by the best rarity and points og:image at the team image", %{conn: conn} do
      token = team_token(@team)
      html = conn |> get(~p"/share/team/#{token}") |> html_response(200)

      assert html =~ "Scavenger team — legendary"
      assert html =~ "/share/team/#{token}/image"
    end

    test "lies on the region's map, the card showing a location by the names' hash", %{conn: conn} do
      html = conn |> get(~p"/share/team/#{team_token(@team)}") |> html_response(200)
      location = expected_location(Enum.map_join(@team, &elem(&1, 0)))

      assert html =~ "share-map-page raid-location-#{location}"
      assert html =~ "share-art-#{location}" and html =~ "Норвинская область"
    end

    test "rejects broken tokens", %{conn: conn} do
      for token <- [
            "not base64!",
            team_token([{"", "rare"}]),
            Base.url_encode64("no separator", padding: false),
            team_token(List.duplicate({"A B", "common"}, 6)),
            team_token([{"Alice Adams", "rare"}, {"Bob Brown", "mythic"}])
          ] do
        assert conn |> get(~p"/share/team/#{token}") |> html_response(400) =~ "invalid link"
      end
    end

    test "renders a PNG card", %{conn: conn} do
      conn = get(conn, ~p"/share/team/#{team_token(@team)}/image")
      assert valid_png?(response(conn, 200))
      assert ["image/png" <> _] = get_resp_header(conn, "content-type")
    end
  end

  describe "raid/2 and raid_og_image/2" do
    @raid_report %{
      location: :customs,
      exit: :exit_train,
      members: [
        %{name: "Alice Adams", rarity: :rare, alive: true},
        %{name: "Bob Brown", rarity: :common, alive: false}
      ],
      loot: [:sj6],
      lang: "en"
    }

    defp raid_token, do: Report.encode(@raid_report)

    test "tells where and how the raid went, who made it, the loot", %{conn: conn} do
      html = conn |> get(~p"/share/raid/#{raid_token()}") |> html_response(200)

      # the page in the visitor's language (Russian by default)
      assert html =~ "Таможня" and html =~ "Вышли 1 из 2" and html =~ "Выход: Поезд"
      assert html =~ "Alice Adams" and html =~ "Bob Brown" and html =~ "погиб"
      assert html =~ "share-raid-lost"
      assert html =~ ~s(href="/raid")
    end

    test "lies on the region's map, the card showing its location", %{conn: conn} do
      html = conn |> get(~p"/share/raid/#{raid_token()}") |> html_response(200)

      assert html =~ "share-map-page raid-location-customs"
      assert html =~ "share-art-customs" and html =~ "Норвинская область"

      # a raid of no location: the region's own scene, and still an image
      token = Report.encode(%{@raid_report | location: nil})
      assert conn |> get(~p"/share/raid/#{token}") |> html_response(200) =~ "share-art-default"

      assert conn
             |> recycle()
             |> get(~p"/share/raid/#{token}/image")
             |> response(200)
             |> valid_png?()
    end

    test "its preview is in the language the raid was told in", %{conn: conn} do
      html = conn |> get(~p"/share/raid/#{raid_token()}") |> html_response(200)

      assert html =~ ~s(<meta property="og:title" content="Raid: Customs")
      assert html =~ "/share/raid/#{raid_token()}/image"
    end

    test "a token that isn't a raid's is a bad request", %{conn: conn} do
      assert conn |> get(~p"/share/raid/not-a-raid") |> html_response(400)
    end

    test "its image is revalidated by an ETag of its token and of how it's drawn", %{conn: conn} do
      path = ~p"/share/raid/#{raid_token()}/image"
      [etag] = conn |> get(path) |> get_resp_header("etag")

      assert build_conn() |> put_req_header("if-none-match", etag) |> get(path) |> response(304)

      # an ETag of the token alone (as before the images' version was in it) is stale
      stale = ~s("#{:crypto.hash(:md5, "raid:" <> raid_token()) |> Base.encode16(case: :lower)}")
      assert build_conn() |> put_req_header("if-none-match", stale) |> get(path) |> response(200)
    end

    test "its image is a PNG, for any token", %{conn: conn} do
      conn = get(conn, ~p"/share/raid/#{raid_token()}/image")
      assert valid_png?(response(conn, 200))
      assert ["image/png" <> _] = get_resp_header(conn, "content-type")

      assert conn |> recycle() |> get(~p"/share/raid/not-a-raid/image") |> response(200)
    end
  end
end
