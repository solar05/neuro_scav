defmodule NeuroScavWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as flashes, inputs and
  buttons. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: NeuroScavWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 mr-2 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for the types.

  ## Examples

      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(color date datetime-local email file month number password
               range search tel text time url week)

  attr :errors, :list, default: []

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :path, :string, required: true
  attr :action, :string, required: true
  slot :inner_block, required: true

  def navlink(%{path: path, action: action} = assigns) do
    assigns =
      assigns
      |> assign(:destination_url, path)
      |> assign(:selected, navlink_class(path, action))

    ~H"""
    <a class={["nav-item", @selected]} href={@destination_url}>{render_slot(@inner_block)}</a>
    """
  end

  @doc """
  Page menu: the current page (Single by default) in the navbar, the rest in a dropdown.
  """
  attr :action, :atom, required: true

  def nav_menu(%{action: action} = assigns) do
    items = [
      {"/", gettext("Single")},
      {"/team_scavengers", gettext("Team")},
      {"/statistics", gettext("Stats")},
      {"/wheel", gettext("Wheel")},
      {"/battle", gettext("Battle")},
      {"/quiz", gettext("Quiz")},
      {"/raid", gettext("Raid")}
    ]

    {current_path, current_label} =
      Enum.find(items, hd(items), fn {path, _} -> active_navlink?(path, action) end)

    assigns =
      assigns
      |> assign(:items, items)
      |> assign(:current_label, current_label)
      |> assign(:summary_class, navlink_class(current_path, action))
      |> assign(:is_old, old_buttons?(action))

    ~H"""
    <details class={["nav-item lang-dropdown nav-dropdown", @is_old && "lang-dropdown-old"]}>
      <summary class={@summary_class}>
        <span class="nav-dropdown-label">{@current_label}</span>
        <span class="lang-dropdown-arrow">▾</span>
      </summary>
      <div class="lang-dropdown-menu">
        <a
          :for={{path, label} <- @items}
          class={["lang-dropdown-item", active_navlink?(path, @action) && "lang-dropdown-item-active"]}
          href={path}
        >
          {label}
        </a>
      </div>
    </details>
    """
  end

  defp navlink_class(path, action) do
    selected_class =
      if old_buttons?(action) && old_path?(path) do
        if active_navlink?(path, action),
          do: "nav-link blended-old-nav",
          else: "nav-link blend-old-font"
      else
        if active_navlink?(path, action),
          do: "nav-link blended-active",
          else: "nav-link blend-font"
      end

    ai_powered_class =
      if old_buttons?(action) && path == "/neuro_scavengers" do
        "ai-badge"
      else
        ""
      end

    "#{selected_class} #{ai_powered_class}" |> String.trim()
  end

  defp old_buttons?(action) do
    action in [
      :single_scavenger,
      :team_scavengers,
      :statistics,
      :glossary,
      :wheel,
      :battle,
      :quiz,
      :raid
    ]
  end

  defp old_path?(path) do
    path in [
      "/",
      "/team_scavengers",
      "/statistics",
      "/glossary",
      "/wheel",
      "/battle",
      "/quiz",
      "/raid"
    ]
  end

  defp active_navlink?("/", :single_scavenger), do: true
  defp active_navlink?(path, action), do: path == "/#{action}"

  attr :lang, :string, required: true
  attr :path, :string, required: true
  attr :action, :atom, required: true
  slot :inner_block, required: false

  def locale_link(%{lang: lang, path: path, action: action} = assigns) do
    effective_lang = lang || "ru"
    locales = [{"RU", "ru"}, {"EN", "en"}, {"DE", "de"}, {"JA", "ja"}]

    current_label =
      locales
      |> Enum.find({"RU", "ru"}, fn {_, code} -> code == effective_lang end)
      |> elem(0)

    items =
      Enum.map(locales, fn {label, code} ->
        %{label: label, href: "#{path}?lang=#{code}", active: code == effective_lang}
      end)

    assigns =
      assigns
      |> assign(:current_label, current_label)
      |> assign(:items, items)
      |> assign(:is_old, old_buttons?(action))

    ~H"""
    <details class={"lang-dropdown#{if @is_old, do: " lang-dropdown-old"}"}>
      <summary class="lang-dropdown-btn">
        {@current_label} <span class="lang-dropdown-arrow">▾</span>
      </summary>
      <div class="lang-dropdown-menu">
        <%= for item <- @items do %>
          <a
            class={"lang-dropdown-item#{if item.active, do: " lang-dropdown-item-active"}"}
            href={item.href}
          >
            {item.label}
          </a>
        <% end %>
      </div>
    </details>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Renders a button that copies a link: the share card of a scavenger or a whole
  team, or any other `path` of the site.

  ## Examples

      <.share_button name="Alice Adams" rarity={:rare} />
      <.share_button team={[%{name: "Alice Adams", rarity: :rare}]} />
      <.share_button path={~p"/battle/abc"} label="Copy invite" />
  """
  attr :name, :string, default: nil
  attr :rarity, :any, default: nil
  attr :team, :list, default: nil, doc: "members with :name and :rarity"
  attr :path, :string, default: nil
  attr :label, :string, default: nil
  attr :class, :string, default: "btn-old-blended"

  def share_button(assigns) do
    assigns = assign(assigns, :path, share_path(assigns))

    ~H"""
    <p class="lead mt-2">
      <button
        class={"btn #{@class} btn-lg blended d-flex justify-content-center w-100"}
        data-url={@path}
        onclick={share_js()}
      >
        {@label || gettext("Share")}
      </button>
    </p>
    """
  end

  @doc """
  `onclick` of a link button with the link in `data-url` (absolute or from the
  site root): the system share sheet on touch devices, a copy elsewhere.
  Inline, because the share pages don't load app.js. An inline handler sees
  `document`'s properties before globals, so a bare `URL` is the string
  `document.URL`: the constructor has to be `window.URL`.
  """
  def share_js do
    "var btn=this, url=new window.URL(btn.dataset.url, location.href).href;" <>
      " if (navigator.share && matchMedia('(pointer: coarse)').matches) { navigator.share({url: url}).catch(function(){}); return; }" <>
      " navigator.clipboard.writeText(url).then(function(){var orig=btn.textContent; btn.textContent='✓'; setTimeout(function(){btn.textContent=orig;},1500);});"
  end

  @doc """
  Renders the stat rows of a battle card (`NeuroScav.BattleRoom.card/1`).

  Stats in `won` are highlighted; `first_round` numbers the rows for the
  battle reveal animation; `hidden` shows "?" instead of the values (the
  values never reach the page); `bonus` (`%{stat => n}`, e.g. raid loot) is
  added to the values and shown beside them.
  """
  attr :card, :map, required: true
  attr :won, :list, default: []
  attr :first_round, :integer, default: 0
  attr :hidden, :boolean, default: false
  attr :bonus, :map, default: %{}

  def card_stats(assigns) do
    ~H"""
    <ul class="battle-stats">
      <li
        :for={{stat, i} <- Enum.with_index(NeuroScav.BattleRoom.stats())}
        class={["battle-stat", stat in @won && "battle-stat-win"]}
        style={"--round: #{@first_round + i}"}
        data-stat={stat}
      >
        <span>{NeuroScav.Locale.get_text("Stat #{stat}")}</span>
        <span class="battle-stat-bar">
          <span :if={not @hidden} style={"width: #{@card.stats[stat] + Map.get(@bonus, stat, 0)}%"}></span>
        </span>
        <span class="battle-stat-value">
          <small :if={not @hidden and Map.get(@bonus, stat, 0) != 0} class={bonus_class(@bonus[stat])}>
            {signed(@bonus[stat])}
          </small>
          <b>{if @hidden, do: "?", else: @card.stats[stat] + Map.get(@bonus, stat, 0)}</b>
        </span>
      </li>
    </ul>
    """
  end

  defp bonus_class(bonus) when bonus > 0, do: "stat-bonus stat-bonus-up"
  defp bonus_class(_bonus), do: "stat-bonus stat-bonus-down"

  # "+10", "−5" (a real minus sign)
  defp signed(value) when value < 0, do: "−#{-value}"
  defp signed(value), do: "+#{value}"

  defp share_path(%{path: path}) when is_binary(path), do: path

  # tokens are decoded by NeuroScavWeb.ShareController
  defp share_path(%{team: [_ | _] = team}) do
    members = Enum.map_join(team, "\n", &"#{&1.name}|#{&1.rarity}")
    "/share/team/#{Base.url_encode64(members, padding: false)}"
  end

  defp share_path(%{name: name, rarity: rarity}),
    do: "/share/#{Base.url_encode64("#{name}|#{rarity}", padding: false)}"

  @doc """
  Renders rarity distribution as animated progress bars.

  Shows each rarity's share of the total scavenger count.
  Updates in real-time when statistics change via PubSub.

  ## Example

      <.rarity_bars statistics={@statistics} />
  """
  attr :statistics, :any, required: true

  def rarity_bars(assigns) do
    s = assigns.statistics

    {total, counts} =
      if s do
        c = [s.neuro, s.legendary, s.epic, s.rare, s.uncommon, s.common, s.gnome]
        {Enum.sum(c), c}
      else
        {0, List.duplicate(0, 7)}
      end

    config = [
      {"neuro", gettext("Stats neuro"), "linear-gradient(90deg,#4d6bfe,#00e5ff,#8892f7)"},
      {"legendary", gettext("Stats legendary"), "darkorange"},
      {"epic", gettext("Stats epic"), "darkorchid"},
      {"rare", gettext("Stats rare"), "rgb(37,171,215)"},
      {"uncommon", gettext("Stats uncommon"), "darkgreen"},
      {"common", gettext("Stats common"), "#a5a5a5"},
      {"gnome", gettext("Stats gnome"),
       "linear-gradient(90deg,#ff3232,#ff9600,#50dc50,#00a0ff,#a000ff)"}
    ]

    bars =
      Enum.zip(config, counts)
      |> Enum.map(fn {{cls, label, bg}, count} ->
        pct = if total > 0, do: Float.round(count / total * 100, 1), else: 0.0
        %{cls: cls, label: label, bg: bg, pct: pct}
      end)

    assigns = assign(assigns, bars: bars, total: total)

    ~H"""
    <div class="rarity-bars-container">
      <p class="rarity-bars-total">{gettext("Stats total")}: {@total}</p>
      <div :for={bar <- @bars} class="rarity-bar-row">
        <span class={"rarity-bar-label #{bar.cls}"}>{bar.label}</span>
        <div class="rarity-bar-track">
          <div class="rarity-bar-fill" style={"width: #{bar.pct}%; background: #{bar.bg};"}></div>
        </div>
        <span class="rarity-bar-pct">{bar.pct}%</span>
      </div>
    </div>
    """
  end
end
