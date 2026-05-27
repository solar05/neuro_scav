defmodule NeuroScavWeb.ShareController do
  use NeuroScavWeb, :controller

  @card_themes ~w(void lava swamp arctic storm rust toxic blood abyss nebula)

  @canvas_w 1200
  @canvas_h 630
  @card_cx 450
  @card_cy 75
  @card_cw 300
  @card_ch 480
  @card_art_h 215

  # Theme SVG inner content loaded at compile time (outer <svg> tags stripped)
  @theme_svgs Map.new(@card_themes, fn theme ->
                content =
                  Path.join([
                    to_string(:code.priv_dir(:neuro_scav)),
                    "static",
                    "images",
                    "share",
                    "#{theme}.svg"
                  ])
                  |> File.read!()
                  |> String.replace(~r/\A\s*<svg[^>]*>/, "")
                  |> String.replace(~r/<\/svg>\s*\z/, "")

                {theme, content}
              end)

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
    "gnome" => {"#ff44bb", "#ffe044"}
  }

  def show(conn, %{"token" => token}) do
    case decode_token(token) do
      {:ok, name, rarity} ->
        conn
        |> put_root_layout(html: {NeuroScavWeb.Layouts, :share})
        |> put_layout(false)
        |> render(:show, name: name, rarity: rarity, theme: pick_theme(name), token: token)

      :error ->
        conn
        |> put_status(:bad_request)
        |> put_root_layout(html: {NeuroScavWeb.Layouts, :share})
        |> put_layout(false)
        |> render(:show, name: nil, rarity: nil, theme: "void", token: token)
    end
  end

  def og_image(conn, %{"token" => token}) do
    {name, rarity, theme} =
      case decode_token(token) do
        {:ok, name, rarity} -> {name, rarity, pick_theme(name)}
        :error -> {"???", "common", "void"}
      end

    etag = :crypto.hash(:md5, token) |> Base.encode16(case: :lower)

    if get_req_header(conn, "if-none-match") == [~s("#{etag}")] do
      conn
      |> put_resp_header("etag", ~s("#{etag}"))
      |> send_resp(304, "")
    else
      conn
      |> put_resp_content_type("image/svg+xml")
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> put_resp_header("etag", ~s("#{etag}"))
      |> send_resp(200, build_og_svg(name, rarity, theme))
    end
  end

  defp pick_theme(name) do
    Enum.at(@card_themes, :erlang.phash2(name, length(@card_themes)))
  end

  # canvas 1200×630, card 300×480 centered → cx=450, cy=75, mid_x=600
  defp build_og_svg(name, rarity, theme) do
    {border_color, text_color} = Map.get(@rarity_colors, rarity, {"#888888", "#aaaaaa"})
    theme_inner = Map.get(@theme_svgs, theme, @theme_svgs["void"])

    badge_label = rarity |> String.upcase() |> xml_escape()
    lines = name |> String.split(" ", parts: 3) |> Enum.map(&xml_escape/1)
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

    cx = @card_cx
    cy = @card_cy
    cw = @card_cw
    ch = @card_ch
    art_h = @card_art_h
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

    tspans = name_tspans(lines, mid_x, line_h)

    decorations = rarity_decorations(rarity, border_color, cx, cy, cw, ch)

    name_box_fill = "url(#name-grad)"
    name_grad_def = name_gradient(rarity, border_color, text_color)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@canvas_w}" height="#{@canvas_h}">
      <defs>
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
        <clipPath id="card-clip">
          <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20"/>
        </clipPath>
        #{name_grad_def}
      </defs>
      <rect width="#{@canvas_w}" height="#{@canvas_h}" fill="#000000"/>
      <rect x="#{cx + 6}" y="#{cy + 6}" width="#{cw}" height="#{ch}" rx="20" fill="#{border_color}" opacity="0.15"/>
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="#0d0d12"/>
      <g clip-path="url(#card-clip)">
        <svg x="#{cx}" y="#{cy}" width="#{cw}" height="#{art_h}" viewBox="0 0 320 160" preserveAspectRatio="xMidYMid slice">
          #{theme_inner}
        </svg>
      </g>
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
            font-family="BenderBold, Arial, sans-serif"
            font-size="18" letter-spacing="2"
            fill="#{border_color}" fill-opacity="0.9" text-anchor="middle">#{badge_label}</text>
      <text x="#{cx + cw - 14}" y="#{cy + ch - 16}"
            font-family="Bender, 'Courier New', monospace"
            font-size="16" font-weight="bold" letter-spacing="2"
            fill="#{border_color}" fill-opacity="0.35" text-anchor="end">SCAVGEN</text>
    </svg>
    """
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

  defp rarity_decorations(rarity, color, cx, cy, cw, ch) do
    mid_x = cx + div(cw, 2)

    tl = cbracket(cx - 8, cy - 8, 22, 1, 1, color)
    tr = cbracket(cx + cw + 8, cy - 8, 22, -1, 1, color)
    bl = cbracket(cx - 8, cy + ch + 8, 22, 1, -1, color)
    br = cbracket(cx + cw + 8, cy + ch + 8, 22, -1, -1, color)

    diamond = fn x, y, r ->
      ~s(<polygon points="#{x},#{y - r} #{x + r},#{y} #{x},#{y + r} #{x - r},#{y}" fill="#{color}"/>)
    end

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
          diamond.(mid_x, cy, 6),
          diamond.(mid_x, cy + ch, 6),
          diamond.(cx, mid_y, 5),
          diamond.(cx + cw, mid_y, 5),
          diamond.(cx + div(cw, 4), cy, 3),
          diamond.(cx + div(cw * 3, 4), cy, 3),
          diamond.(cx + div(cw, 4), cy + ch, 3),
          diamond.(cx + div(cw * 3, 4), cy + ch, 3)
        ]
        |> Enum.join("\n")

      "epic" ->
        mid_y = cy + div(ch, 2)

        [
          inner_glow,
          tl,
          tr,
          bl,
          br,
          diamond.(mid_x, cy, 5),
          diamond.(mid_x, cy + ch, 5),
          diamond.(cx, mid_y, 4),
          diamond.(cx + cw, mid_y, 4)
        ]
        |> Enum.join("\n")

      "rare" ->
        mid_y = cy + div(ch, 2)

        [
          tl,
          tr,
          diamond.(mid_x, cy, 4),
          diamond.(cx, mid_y, 3),
          diamond.(cx + cw, mid_y, 3)
        ]
        |> Enum.join("\n")

      "uncommon" ->
        [tl, tr] |> Enum.join("\n")

      "gnome" ->
        rainbow = ~w(#ff6b6b #ffaa33 #ffe044 #44ee88 #44aaff #bb55ff #ff44bb)

        rdiamond = fn x, y, r, c ->
          ~s(<polygon points="#{x},#{y - r} #{x + r},#{y} #{x},#{y + r} #{x - r},#{y}" fill="#{c}"/>)
        end

        top_diamonds =
          rainbow
          |> Enum.with_index()
          |> Enum.map(fn {c, i} ->
            rdiamond.(cx + 20 + i * 40, cy, if(i == 3, do: 6, else: 4), c)
          end)

        bottom_diamonds =
          rainbow
          |> Enum.with_index()
          |> Enum.map(fn {c, i} ->
            rdiamond.(cx + 20 + i * 40, cy + ch, if(i == 3, do: 6, else: 4), c)
          end)

        side_diamonds =
          rainbow
          |> Enum.with_index()
          |> Enum.flat_map(fn {c, i} ->
            y = cy + 40 + i * 57
            [rdiamond.(cx, y, 4, c), rdiamond.(cx + cw, y, 4, c)]
          end)

        ([inner_glow, tl, tr, bl, br] ++ top_diamonds ++ bottom_diamonds ++ side_diamonds)
        |> Enum.join("\n")

      _ ->
        ""
    end
  end

  defp cbracket(x, y, arm, dx, dy, color) do
    ~s(<path d="M #{x},#{y + dy * arm} L #{x},#{y} L #{x + dx * arm},#{y}" fill="none" stroke="#{color}" stroke-width="2"/>)
  end

  defp xml_escape(str) do
    str |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
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
end
