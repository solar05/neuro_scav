defmodule NeuroScavWeb.ShareController do
  use NeuroScavWeb, :controller

  @card_themes ~w(void lava swamp arctic storm rust toxic blood abyss nebula)

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
    "legendary" => {"#ff8c00", "#ff8c00"},
    "epic" => {"#9932cc", "#9932cc"},
    "rare" => {"#1e90ff", "#25abd7"},
    "uncommon" => {"#006400", "#006400"},
    "common" => {"#888888", "#444444"}
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

    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_resp(200, build_og_svg(name, rarity, theme))
  end

  defp pick_theme(name) do
    index = abs(:erlang.phash2(name)) |> rem(length(@card_themes))
    Enum.at(@card_themes, index)
  end

  # canvas 1200×630, card 300×480 centered → cx=450, cy=75, mid_x=600
  defp build_og_svg(name, rarity, theme) do
    {border_color, name_box_color} = Map.get(@rarity_colors, rarity, {"#888888", "#444444"})
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

    cx = 450
    cy = 75
    cw = 300
    ch = 480
    art_h = 215
    mid_x = cx + div(cw, 2)

    name_box_x = cx + 15
    name_box_w = cw - 30
    name_box_y = cy + art_h + 12
    name_box_bottom = name_box_y + name_box_h

    # Center text block vertically in name box
    text_block_h = (num_lines - 1) * line_h
    name_text_y = name_box_y + div(name_box_h - text_block_h, 2) + div(font_size * 2, 3)

    badge_w = 120
    badge_h = 32
    badge_x = mid_x - div(badge_w, 2)
    badge_y = name_box_bottom + 10

    tspans =
      lines
      |> Enum.with_index()
      |> Enum.map_join("\n      ", fn {line, i} ->
        dy = if i == 0, do: 0, else: line_h
        ~s(<tspan x="#{mid_x}" dy="#{dy}">#{line}</tspan>)
      end)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
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
        </style>
        <clipPath id="card-clip">
          <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20"/>
        </clipPath>
      </defs>
      <rect width="1200" height="630" fill="#000000"/>
      <rect x="#{cx + 6}" y="#{cy + 6}" width="#{cw}" height="#{ch}" rx="20" fill="#{border_color}" opacity="0.15"/>
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="#0d0d12"/>
      <g clip-path="url(#card-clip)">
        <svg x="#{cx}" y="#{cy}" width="#{cw}" height="#{art_h}" viewBox="0 0 320 160" preserveAspectRatio="xMidYMid slice">
          #{theme_inner}
        </svg>
      </g>
      <rect x="#{cx}" y="#{cy}" width="#{cw}" height="#{ch}" rx="20" fill="none" stroke="#{border_color}" stroke-width="4"/>
      <rect x="#{name_box_x}" y="#{name_box_y}" width="#{name_box_w}" height="#{name_box_h}" rx="16" fill="#{name_box_color}"/>
      <text x="#{mid_x}" y="#{name_text_y}"
            font-family="Bender, Arial, sans-serif"
            font-size="#{font_size}" font-weight="bold"
            fill="#ffffff" text-anchor="middle">
        #{tspans}
      </text>
      <rect x="#{badge_x}" y="#{badge_y}" width="#{badge_w}" height="#{badge_h}" rx="16" fill="#16161e"/>
      <text x="#{mid_x}" y="#{badge_y + 22}"
            font-family="Bender, Arial, sans-serif"
            font-size="12" font-weight="bold" letter-spacing="2"
            fill="#aaaaaa" text-anchor="middle">#{badge_label}</text>
      <text x="#{cx + cw - 14}" y="#{cy + ch - 16}"
            font-family="Bender, 'Courier New', monospace"
            font-size="11" fill="#444444" text-anchor="end">scavgen</text>
    </svg>
    """
  end

  defp xml_escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp decode_token(token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         [name, rarity] <- String.split(decoded, "|", parts: 2) do
      {:ok, name, rarity}
    else
      _ -> :error
    end
  end
end
