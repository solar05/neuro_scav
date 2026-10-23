defmodule NeuroScavWeb.ShareController do
  use NeuroScavWeb, :controller

  alias NeuroScav.Raid.Report
  alias NeuroScavWeb.RaidComponents

  @canvas %{w: 1200, h: 630}
  @card %{cx: 450, cy: 75, cw: 300, ch: 480, art_h: 215}

  # Fonts embedded as base64 at compile time so the SVG is self-contained
  @font_normal Path.join([
                 to_string(:code.priv_dir(:neuro_scav)),
                 "static",
                 "fonts",
                 "Bender.otf"
               ])
               |> File.read!()
               |> Base.encode64()

  @font_bold Path.join([
               to_string(:code.priv_dir(:neuro_scav)),
               "static",
               "fonts",
               "BenderBold.otf"
             ])
             |> File.read!()
             |> Base.encode64()

  @rarity_colors %{
    "legendary" => {"#ff8c00", "#ffd060"},
    "epic" => {"#9932cc", "#cc80ff"},
    "rare" => {"#1e90ff", "#80d0ff"},
    "uncommon" => {"#22aa44", "#66cc88"},
    "common" => {"#888888", "#aaaaaa"},
    "gnome" => {"#ff44bb", "#ffe044"},
    "neuro" => {"#4d6bfe", "#00e5ff"}
  }

  # best first; picks the team card's frame color
  @rarity_rank ~w(gnome legendary epic neuro rare uncommon common)
  @max_team_members NeuroScav.ScavengersServer.max_team_members()
  @team_card %{cx: 320, cy: 75, cw: 560, ch: 480, art_h: 110}
  @raid_card %{cx: 220, cy: 45, cw: 760, ch: 540, art_h: 150}

  # A share card's art (priv/static/images/share), inner content read at
  # compile time (outer <svg> tags stripped): a scene of each location for the
  # card's strip (640×200, "default" for a raid of no location), the region's
  # tactical map behind the card. A raid shows where it went; a scavenger, a
  # team where they were spotted, by their names' hash.
  @share_images Path.join([to_string(:code.priv_dir(:neuro_scav)), "static", "images", "share"])
  @location_art Map.new(Path.wildcard(Path.join(@share_images, "locations/*.svg")), fn path ->
                  content =
                    path
                    |> File.read!()
                    |> String.replace(~r/\A\s*<svg[^>]*>/, "")
                    |> String.replace(~r/<\/svg>\s*\z/, "")

                  {Path.basename(path, ".svg"), content}
                end)
  @region_map Path.join(@share_images, "map.svg")
              |> File.read!()
              |> String.replace(~r/\A\s*<svg[^>]*>/, "")
              |> String.replace(~r/<\/svg>\s*\z/, "")
  @locations NeuroScav.Raid.locations()
  # a location's colour washing over the map, as over the raid's own map card
  @location_tints %{
    customs: "#c29a54",
    woods: "#4c8c4a",
    shoreline: "#3884a0",
    interchange: "#965abe",
    reserve: "#82823c",
    lighthouse: "#5a78aa",
    streets: "#aa503c",
    factory: "#a06e3c",
    labs: "#78c8d2"
  }

  def show(conn, %{"token" => token}) do
    case decode_token(token) do
      {:ok, name, rarity} ->
        conn
        |> put_share_layout()
        |> merge_assigns(location_assigns(pick_location(name)))
        |> render(:show,
          name: name,
          rarity: rarity,
          token: token,
          title: "#{name} — #{rarity}",
          description: "A #{rarity} scavenger from scavgen",
          share_path: ~p"/share/#{token}"
        )

      :error ->
        conn
        |> put_status(:bad_request)
        |> put_share_layout()
        |> render(:show, name: nil, rarity: nil, token: token)
    end
  end

  def team(conn, %{"token" => token}) do
    case decode_team_token(token) do
      {:ok, members} ->
        best = best_rarity(members)

        conn
        |> put_share_layout()
        |> merge_assigns(location_assigns(pick_location(Enum.map_join(members, & &1.name))))
        |> render(:team,
          members: Enum.map(members, &Map.put(&1, :color, rarity_color(&1.rarity))),
          border_color: rarity_color(best),
          token: token,
          title: "Scavenger team — #{best}",
          description: Enum.map_join(members, ", ", & &1.name),
          share_path: ~p"/share/team/#{token}"
        )

      :error ->
        conn
        |> put_status(:bad_request)
        |> put_share_layout()
        |> render(:show, name: nil, rarity: nil, token: token)
    end
  end

  # A finished raid (NeuroScav.Raid.Report): the page in the visitor's
  # language, its preview (title, description, image) in the one it was told in.
  def raid(conn, %{"token" => token}) do
    case Report.decode(token) do
      {:ok, report} ->
        {title, description} =
          Gettext.with_locale(NeuroScavWeb.Gettext, report.lang, fn -> raid_meta(report) end)

        conn
        |> put_share_layout()
        |> merge_assigns(location_assigns(report.location))
        |> render(:raid,
          location: report.location && RaidComponents.location_title(report.location),
          verdict: raid_verdict(report),
          exit: report.exit && RaidComponents.event_title(report.exit),
          members: Enum.map(report.members, &raid_member/1),
          loot: RaidComponents.loot_text(report.loot),
          border_color: raid_color(report),
          token: token,
          title: title,
          description: description,
          share_path: ~p"/share/raid/#{token}"
        )

      :error ->
        conn
        |> put_status(:bad_request)
        |> put_share_layout()
        |> render(:show, name: nil, rarity: nil, token: token)
    end
  end

  def raid_og_image(conn, %{"token" => token}) do
    case Report.decode(token) do
      {:ok, report} ->
        send_png(conn, "raid:" <> token, fn -> raid_og_svg(report) end)

      :error ->
        send_png(conn, "raid:?", fn -> build_og_svg("???", "common", nil) end)
    end
  end

  # the image in the language the raid was told in
  defp raid_og_svg(report),
    do:
      Gettext.with_locale(NeuroScavWeb.Gettext, report.lang, fn -> build_raid_og_svg(report) end)

  defp raid_title(%{location: nil}), do: gettext("Raid")

  defp raid_title(report),
    do:
      gettext("Raid share title %{location}",
        location: RaidComponents.location_title(report.location)
      )

  defp raid_verdict(report),
    do:
      RaidComponents.verdict_text(Enum.count(report.members, & &1.alive), length(report.members))

  defp raid_exit(%{exit: nil}), do: nil

  defp raid_exit(report),
    do: gettext("Raid exited %{exit}", exit: RaidComponents.event_title(report.exit))

  defp raid_meta(report) do
    description =
      [raid_verdict(report), raid_exit(report), RaidComponents.loot_text(report.loot)]
      |> Enum.filter(& &1)
      |> Enum.join(" · ")

    {raid_title(report), description}
  end

  # a member as the page shows them: how they came out, in their rarity's colour or the dead's red
  defp raid_member(member) do
    %{
      name: member.name,
      alive: member.alive,
      status:
        if(member.alive,
          do: RaidComponents.rarity_name(member.rarity),
          else: gettext("Raid result kia")
        ),
      color: if(member.alive, do: rarity_color(to_string(member.rarity)), else: "#e53935")
    }
  end

  # all out green, nobody red, the rest gold
  defp raid_color(report) do
    case Enum.count(report.members, & &1.alive) do
      0 -> "#e53935"
      alive when alive == length(report.members) -> "#4caf50"
      _some -> "#d49300"
    end
  end

  def og_image(conn, %{"token" => token}) do
    {name, rarity, location} =
      case decode_token(token) do
        {:ok, name, rarity} -> {name, rarity, pick_location(name)}
        :error -> {"???", "common", nil}
      end

    send_png(conn, token, fn ->
      Gettext.with_locale(NeuroScavWeb.Gettext, "en", fn ->
        build_og_svg(name, rarity, location)
      end)
    end)
  end

  def team_og_image(conn, %{"token" => token}) do
    members =
      case decode_team_token(token) do
        {:ok, members} -> members
        :error -> [%{name: "???", rarity: "common"}]
      end

    location = pick_location(Enum.map_join(members, & &1.name))

    send_png(conn, "team:" <> token, fn ->
      Gettext.with_locale(NeuroScavWeb.Gettext, "en", fn ->
        build_team_og_svg(members, location)
      end)
    end)
  end

  defp put_share_layout(conn) do
    conn
    |> put_root_layout(html: {NeuroScavWeb.Layouts, :share})
    |> put_layout(false)
  end

  defp send_png(conn, cache_key, build_svg) do
    etag = :crypto.hash(:md5, cache_key) |> Base.encode16(case: :lower)

    if get_req_header(conn, "if-none-match") == [~s("#{etag}")] do
      conn
      |> put_resp_header("etag", ~s("#{etag}"))
      |> send_resp(304, "")
    else
      result =
        try do
          Resvg.svg_string_to_png_buffer(build_svg.(),
            font_files: font_paths(),
            skip_system_fonts: true,
            resources_dir: System.tmp_dir!()
          )
        rescue
          e -> {:error, e}
        end

      case result do
        {:ok, buffer} ->
          conn
          |> put_resp_content_type("image/png", nil)
          |> put_resp_header("cache-control", "public, max-age=86400")
          |> put_resp_header("etag", ~s("#{etag}"))
          |> send_resp(200, :binary.list_to_bin(buffer))

        {:error, reason} ->
          require Logger
          Logger.error("og_image render failed for #{cache_key}: #{inspect(reason)}")
          send_resp(conn, 503, "")
      end
    end
  end

  defp pick_location(name) do
    Enum.at(@locations, :erlang.phash2(name, length(@locations)))
  end

  # a share page's location: the scene on its card's strip, the colour over
  # the map behind it
  defp location_assigns(location) do
    [
      art: to_string(location || :default),
      location_class: location && "raid-location-#{location}"
    ]
  end

  # the region's tactical map under a share card, washed in its location's
  # colour and darker at the edges; the region's name over the card's corner
  defp region_backdrop(location, %{cx: cx, cy: cy}) do
    """
      <defs>
        <radialGradient id="vignette" cx="50%" cy="50%" r="70%">
          <stop offset="0" stop-color="#000000" stop-opacity="0.1"/>
          <stop offset="1" stop-color="#000000" stop-opacity="0.8"/>
        </radialGradient>
      </defs>
      <rect width="#{@canvas.w}" height="#{@canvas.h}" fill="#0d110b"/>
      <svg width="#{@canvas.w}" height="#{@canvas.h}" viewBox="0 0 1200 800" preserveAspectRatio="xMidYMid slice">
        #{@region_map}
      </svg>
      <rect width="#{@canvas.w}" height="#{@canvas.h}" fill="#{Map.get(@location_tints, location, "#000000")}" opacity="0.12"/>
      <rect width="#{@canvas.w}" height="#{@canvas.h}" fill="url(#vignette)"/>
      <text x="#{cx}" y="#{cy - 14}" font-family="Bender, Arial, sans-serif" font-size="15" font-weight="bold" letter-spacing="3" fill="#9aab68">#{gettext("Share region") |> String.upcase() |> xml_escape()}</text>
    """
  end

  # a share card's strip: its location's scene, the ground kept
  defp location_strip(location, %{cx: cx, cy: cy, cw: cw, art_h: art_h}) do
    """
      <g clip-path="url(#card-clip)">
        <svg x="#{cx}" y="#{cy}" width="#{cw}" height="#{art_h}" viewBox="0 0 640 200" preserveAspectRatio="xMidYMax slice">
          #{Map.fetch!(@location_art, to_string(location || :default))}
        </svg>
      </g>
    """
  end

  # canvas 1200×630, card 300×480 centered → cx=450, cy=75, mid_x=600
  defp build_og_svg(name, rarity, location) do
    {border_color, text_color} = Map.get(@rarity_colors, rarity, {"#888888", "#aaaaaa"})

    badge_label = rarity |> String.upcase() |> xml_escape()
    lines = name |> String.split(" ", parts: 3) |> Enum.map(&xml_escape/1)

    %{cx: cx, cy: cy, cw: cw, ch: ch} = @card

    %{
      font_size: font_size,
      line_h: line_h,
      mid_x: mid_x,
      name_box_x: name_box_x,
      name_box_y: name_box_y,
      name_box_w: name_box_w,
      name_box_h: name_box_h,
      name_text_y: name_text_y,
      badge_x: badge_x,
      badge_y: badge_y,
      badge_w: badge_w,
      badge_h: badge_h
    } = card_layout(lines)

    tspans = name_tspans(lines, mid_x, line_h)

    decorations = rarity_decorations(rarity, border_color, @card)

    name_box_fill = "url(#name-grad)"
    name_grad_def = name_gradient(rarity, border_color, text_color)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@canvas.w}" height="#{@canvas.h}">
      #{font_style_defs()}
      <defs>
        <clipPath id="card-clip">
          <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20"/>
        </clipPath>
        #{name_grad_def}
      </defs>
      #{region_backdrop(location, @card)}
      <rect x="#{cx + 6}" y="#{cy + 6}" width="#{cw}" height="#{ch}" rx="20" fill="#{border_color}" opacity="0.15"/>
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="#0d0d12"/>
      #{location_strip(location, @card)}
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="none" stroke="#{border_color}" stroke-width="4"/>
      #{decorations}
      <line x1="#{cx}" y1="#{name_box_y - 7}" x2="#{cx + cw}" y2="#{name_box_y - 7}" stroke="#{border_color}" stroke-width="1" opacity="0.5"/>
      <rect x="#{name_box_x}" y="#{name_box_y}" width="#{name_box_w}" height="#{name_box_h}" rx="16" fill="#{name_box_fill}"/>
      <text x="#{mid_x}" y="#{name_text_y}"
            font-family="Bender, Arial, sans-serif"
            font-size="#{font_size}" font-weight="bold"
            fill="#ffffff"
            text-anchor="middle">
        #{tspans}
      </text>
      <rect x="#{badge_x}" y="#{badge_y}" width="#{badge_w}" height="#{badge_h}" rx="16" fill="#16161e" stroke="#{border_color}" stroke-width="1" stroke-opacity="0.5"/>
      <text x="#{mid_x}" y="#{badge_y + 22}"
            font-family="Bender, Arial, sans-serif"
            font-size="18" font-weight="bold" letter-spacing="2"
            fill="#{border_color}" fill-opacity="0.9" text-anchor="middle">#{badge_label}</text>
      <text x="#{cx + cw - 14}" y="#{cy + ch - 16}"
            font-family="Bender, 'Courier New', monospace"
            font-size="16" font-weight="bold" letter-spacing="2"
            fill="#{border_color}" fill-opacity="0.35" text-anchor="end">SCAVGEN</text>
    </svg>
    """
  end

  # canvas 1200×630, team card 560×480 centered: the location's strip, then one row per member
  defp build_team_og_svg(members, location) do
    %{cx: cx, cy: cy, cw: cw, ch: ch, art_h: art_h} = @team_card
    best = best_rarity(members)
    border_color = rarity_color(best)

    rows =
      members
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {%{name: name, rarity: rarity}, i} ->
        y = cy + art_h + 20 + i * 62
        color = rarity_color(rarity)

        """
          <rect x="#{cx + 20}" y="#{y}" width="#{cw - 40}" height="52" rx="12" fill="#16161e" stroke="#{color}" stroke-width="2"/>
          <text x="#{cx + 40}" y="#{y + 35}" font-family="Bender, Arial, sans-serif" font-size="26" font-weight="bold" fill="#ffffff">#{name |> String.slice(0, 24) |> xml_escape()}</text>
          <text x="#{cx + cw - 40}" y="#{y + 33}" font-family="Bender, Arial, sans-serif" font-size="16" font-weight="bold" letter-spacing="2" fill="#{color}" text-anchor="end">#{rarity |> String.upcase() |> xml_escape()}</text>
        """
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@canvas.w}" height="#{@canvas.h}">
      #{font_style_defs()}
      <defs>
        <clipPath id="card-clip">
          <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20"/>
        </clipPath>
      </defs>
      #{region_backdrop(location, @team_card)}
      <rect x="#{cx + 6}" y="#{cy + 6}" width="#{cw}" height="#{ch}" rx="20" fill="#{border_color}" opacity="0.15"/>
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="#0d0d12"/>
      #{location_strip(location, @team_card)}
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="none" stroke="#{border_color}" stroke-width="4"/>
      #{rarity_decorations(best, border_color, @team_card)}
      <line x1="#{cx}" y1="#{cy + art_h}" x2="#{cx + cw}" y2="#{cy + art_h}" stroke="#{border_color}" stroke-width="1" opacity="0.5"/>
      #{rows}
      <text x="#{cx + cw - 14}" y="#{cy + ch - 16}"
            font-family="Bender, 'Courier New', monospace"
            font-size="16" font-weight="bold" letter-spacing="2"
            fill="#{border_color}" fill-opacity="0.35" text-anchor="end">SCAVGEN</text>
    </svg>
    """
  end

  # canvas 1200×630, a card 760×540: the art strip, where and how the raid
  # went, a row per member, the loot carried out
  defp build_raid_og_svg(report) do
    %{cx: cx, cy: cy, cw: cw, ch: ch, art_h: art_h} = @raid_card
    color = raid_color(report)
    mid_x = cx + div(cw, 2)
    loot = RaidComponents.loot_text(report.loot)
    loot = if String.length(loot) > 70, do: String.slice(loot, 0, 69) <> "…", else: loot

    rows =
      report.members
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {member, i} ->
        %{name: name, status: status, color: row_color} = raid_member(member)
        y = cy + art_h + 134 + i * 38
        name_color = if member.alive, do: "#ffffff", else: "#8a8a8a"

        """
          <rect x="#{cx + 40}" y="#{y}" width="#{cw - 80}" height="31" rx="10" fill="#16161e" stroke="#{row_color}" stroke-width="2"/>
          <text x="#{cx + 58}" y="#{y + 22}" font-family="Bender, Arial, sans-serif" font-size="20" font-weight="bold" fill="#{name_color}">#{name |> String.slice(0, 30) |> xml_escape()}</text>
          <text x="#{cx + cw - 58}" y="#{y + 21}" font-family="Bender, Arial, sans-serif" font-size="15" font-weight="bold" letter-spacing="2" fill="#{row_color}" text-anchor="end">#{status |> String.upcase() |> xml_escape()}</text>
        """
      end)

    exit_line =
      case raid_exit(report) do
        nil ->
          ""

        text ->
          ~s(<text x="#{mid_x}" y="#{cy + art_h + 110}" font-family="Bender, Arial, sans-serif" font-size="22" fill="#4caf50" text-anchor="middle">#{xml_escape(text)}</text>)
      end

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@canvas.w}" height="#{@canvas.h}">
      #{font_style_defs()}
      <defs>
        <clipPath id="card-clip">
          <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20"/>
        </clipPath>
      </defs>
      #{region_backdrop(report.location, @raid_card)}
      <rect x="#{cx + 6}" y="#{cy + 6}" width="#{cw}" height="#{ch}" rx="20" fill="#{color}" opacity="0.15"/>
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="#0d0d12"/>
      #{location_strip(report.location, @raid_card)}
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="none" stroke="#{color}" stroke-width="4"/>
      <line x1="#{cx}" y1="#{cy + art_h}" x2="#{cx + cw}" y2="#{cy + art_h}" stroke="#{color}" stroke-width="1" opacity="0.5"/>
      <text x="#{mid_x}" y="#{cy + art_h + 42}" font-family="Bender, Arial, sans-serif" font-size="32" font-weight="bold" letter-spacing="2" fill="#d49300" text-anchor="middle">#{report |> raid_title() |> String.upcase() |> xml_escape()}</text>
      <text x="#{mid_x}" y="#{cy + art_h + 80}" font-family="Bender, Arial, sans-serif" font-size="28" font-weight="bold" fill="#ffffff" text-anchor="middle">#{report |> raid_verdict() |> xml_escape()}</text>
      #{exit_line}
      #{rows}
      <text x="#{mid_x}" y="#{cy + ch - 28}" font-family="Bender, Arial, sans-serif" font-size="19" fill="#c8c8c8" text-anchor="middle">#{xml_escape(loot)}</text>
      <text x="#{cx + cw - 14}" y="#{cy + ch - 8}"
            font-family="Bender, 'Courier New', monospace"
            font-size="14" font-weight="bold" letter-spacing="2"
            fill="#{color}" fill-opacity="0.35" text-anchor="end">SCAVGEN</text>
    </svg>
    """
  end

  defp font_style_defs do
    """
    <style>
      @font-face {
        font-family: 'Bender';
        font-weight: normal;
        src: url('data:font/otf;base64,#{@font_normal}') format('opentype');
      }
      @font-face {
        font-family: 'Bender';
        font-weight: bold;
        src: url('data:font/otf;base64,#{@font_bold}') format('opentype');
      }
      @font-face {
        font-family: 'BenderBold';
        src: url('data:font/otf;base64,#{@font_bold}') format('opentype');
      }
    </style>
    """
  end

  defp card_layout(lines) do
    num_lines = length(lines)
    max_part = lines |> Enum.map(&String.length/1) |> Enum.max()

    font_size =
      cond do
        max_part > 14 -> 22
        max_part > 10 -> 26
        num_lines == 1 -> 36
        true -> 30
      end

    line_h = round(font_size * 1.4)
    name_box_h = num_lines * line_h + 32

    %{cx: cx, cy: cy, cw: cw, art_h: art_h} = @card
    mid_x = cx + div(cw, 2)

    name_box_x = cx + 15
    name_box_w = cw - 30
    name_box_y = cy + art_h + 12
    name_box_bottom = name_box_y + name_box_h

    text_block_h = (num_lines - 1) * line_h
    name_text_y = name_box_y + div(name_box_h - text_block_h, 2) + div(font_size * 2, 3) - 10

    badge_w = 120
    badge_h = 32
    badge_x = mid_x - div(badge_w, 2)
    badge_y = name_box_bottom + 10

    %{
      font_size: font_size,
      line_h: line_h,
      mid_x: mid_x,
      name_box_x: name_box_x,
      name_box_y: name_box_y,
      name_box_w: name_box_w,
      name_box_h: name_box_h,
      name_text_y: name_text_y,
      badge_x: badge_x,
      badge_y: badge_y,
      badge_w: badge_w,
      badge_h: badge_h
    }
  end

  defp name_tspans(lines, mid_x, line_h) do
    lines
    |> Enum.with_index()
    |> Enum.map_join("\n      ", fn {line, i} ->
      dy = if i == 0, do: 0, else: line_h
      ~s(<tspan x="#{mid_x}" dy="#{dy}">#{line}</tspan>)
    end)
  end

  defp name_gradient("gnome", _border_color, _text_color) do
    """
          <linearGradient id="name-grad" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%"   stop-color="#ff4444"/>
            <stop offset="14%"  stop-color="#ff8800"/>
            <stop offset="28%"  stop-color="#ffdd00"/>
            <stop offset="43%"  stop-color="#44cc55"/>
            <stop offset="57%"  stop-color="#2299ff"/>
            <stop offset="71%"  stop-color="#9944ff"/>
            <stop offset="85%"  stop-color="#ff44bb"/>
            <stop offset="100%" stop-color="#ff4444"/>
          </linearGradient>
    """
  end

  defp name_gradient(_rarity, border_color, text_color) do
    """
          <linearGradient id="name-grad" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%"   stop-color="#{border_color}"/>
            <stop offset="100%" stop-color="#{text_color}"/>
          </linearGradient>
    """
  end

  defp rarity_decorations(rarity, color, %{cx: cx, cy: cy, cw: cw, ch: ch}) do
    mid_x = cx + div(cw, 2)

    tl = corner_bracket(cx - 8, cy - 8, 22, 1, 1, color)
    tr = corner_bracket(cx + cw + 8, cy - 8, 22, -1, 1, color)
    bl = corner_bracket(cx - 8, cy + ch + 8, 22, 1, -1, color)
    br = corner_bracket(cx + cw + 8, cy + ch + 8, 22, -1, -1, color)

    inner_glow =
      ~s(<rect x="#{cx + 5}" y="#{cy + 5}" width="#{cw - 10}" height="#{ch - 10}" rx="17" fill="none" stroke="#{color}" stroke-width="1" opacity="0.2"/>)

    case rarity do
      "legendary" ->
        mid_y = cy + div(ch, 2)

        [
          inner_glow,
          tl,
          tr,
          bl,
          br,
          diamond_svg(mid_x, cy, 6, color),
          diamond_svg(mid_x, cy + ch, 6, color),
          diamond_svg(cx, mid_y, 5, color),
          diamond_svg(cx + cw, mid_y, 5, color),
          diamond_svg(cx + div(cw, 4), cy, 3, color),
          diamond_svg(cx + div(cw * 3, 4), cy, 3, color),
          diamond_svg(cx + div(cw, 4), cy + ch, 3, color),
          diamond_svg(cx + div(cw * 3, 4), cy + ch, 3, color)
        ]
        |> Enum.join("\n")

      rarity when rarity in ["epic", "neuro"] ->
        mid_y = cy + div(ch, 2)

        [
          inner_glow,
          tl,
          tr,
          bl,
          br,
          diamond_svg(mid_x, cy, 5, color),
          diamond_svg(mid_x, cy + ch, 5, color),
          diamond_svg(cx, mid_y, 4, color),
          diamond_svg(cx + cw, mid_y, 4, color)
        ]
        |> Enum.join("\n")

      "rare" ->
        mid_y = cy + div(ch, 2)

        [
          tl,
          tr,
          diamond_svg(mid_x, cy, 4, color),
          diamond_svg(cx, mid_y, 3, color),
          diamond_svg(cx + cw, mid_y, 3, color)
        ]
        |> Enum.join("\n")

      "uncommon" ->
        [tl, tr] |> Enum.join("\n")

      "gnome" ->
        rainbow = ~w(#ff6b6b #ffaa33 #ffe044 #44ee88 #44aaff #bb55ff #ff44bb)

        top_diamonds =
          rainbow
          |> Enum.with_index()
          |> Enum.map(fn {c, i} ->
            diamond_svg(cx + 20 + i * 40, cy, gnome_diamond_radius(i), c)
          end)

        bottom_diamonds =
          rainbow
          |> Enum.with_index()
          |> Enum.map(fn {c, i} ->
            diamond_svg(cx + 20 + i * 40, cy + ch, gnome_diamond_radius(i), c)
          end)

        side_diamonds =
          rainbow
          |> Enum.with_index()
          |> Enum.flat_map(fn {c, i} ->
            y = cy + 40 + i * 57
            [diamond_svg(cx, y, 4, c), diamond_svg(cx + cw, y, 4, c)]
          end)

        ([inner_glow, tl, tr, bl, br] ++ top_diamonds ++ bottom_diamonds ++ side_diamonds)
        |> Enum.join("\n")

      _ ->
        ""
    end
  end

  defp gnome_diamond_radius(3), do: 6
  defp gnome_diamond_radius(_), do: 4

  defp diamond_svg(x, y, r, color) do
    ~s(<polygon points="#{x},#{y - r} #{x + r},#{y} #{x},#{y + r} #{x - r},#{y}" fill="#{color}"/>)
  end

  defp corner_bracket(x, y, arm, dx, dy, color) do
    ~s(<path d="M #{x},#{y + dy * arm} L #{x},#{y} L #{x + dx * arm},#{y}" fill="none" stroke="#{color}" stroke-width="2"/>)
  end

  defp xml_escape(str) do
    str |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  defp font_paths do
    priv = to_string(:code.priv_dir(:neuro_scav))
    fonts_dir = Path.join([priv, "static", "fonts"])
    [Path.join(fonts_dir, "Bender.otf"), Path.join(fonts_dir, "BenderBold.otf")]
  end

  defp decode_token(token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         [name, rarity] when name != "" and rarity != "" <-
           String.split(decoded, "|", parts: 2) do
      {:ok, name, rarity}
    else
      _ -> :error
    end
  end

  # one "name|rarity" line per member
  defp decode_team_token(token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         lines when length(lines) in 1..@max_team_members <- String.split(decoded, "\n"),
         pairs = Enum.map(lines, &String.split(&1, "|", parts: 2)),
         true <- Enum.all?(pairs, &match?([name, rarity] when name != "" and rarity != "", &1)) do
      {:ok, Enum.map(pairs, fn [name, rarity] -> %{name: name, rarity: rarity} end)}
    else
      _ -> :error
    end
  end

  defp best_rarity(members) do
    members
    |> Enum.map(& &1.rarity)
    |> Enum.min_by(&(Enum.find_index(@rarity_rank, fn r -> r == &1 end) || length(@rarity_rank)))
  end

  defp rarity_color(rarity),
    do: @rarity_colors |> Map.get(rarity, {"#888888", "#aaaaaa"}) |> elem(0)
end
