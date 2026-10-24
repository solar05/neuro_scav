defmodule NeuroScavWeb.RaidLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NeuroScav.Raid.Catalog
  alias NeuroScav.{RaidStore, ScavengersServer}
  alias NeuroScavWeb.NeuroScavengerLive.Raid

  setup do
    start_supervised!({NeuroScav.ScavengersServer, %{module_name: NeuroScav.Scavengers.Names}})
    :ok
  end

  defp members(view),
    do:
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(".raid-member")
      |> Enum.count()

  # into the raid: where it starts with picking a way in, the first one
  defp enter(view) do
    if has_element?(view, "#raid-moves"), do: view |> element("#raid-option-0") |> render_click()
    view
  end

  # takes the first option there is to take (a locked retreat isn't) until the raid ends
  defp finish(view) do
    if has_element?(view, "#raid-end") do
      view
    else
      [id | _open] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(".raid-option:not([disabled])")
        |> LazyHTML.attribute("id")

      view |> element("##{id}") |> render_click()
      finish(view)
    end
  end

  test "recruits a squad of five and walks it through the encounters", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/raid")
    assert html =~ "Набрать отряд"
    # the marker that hides the gnome popup on this page (app.css)
    assert has_element?(lv, ".raid-page")

    lv |> element("#btn-raid-recruit") |> render_click()
    assert members(lv) == 5
    # the whole map, and a few layers round the squad for a phone
    assert has_element?(lv, "#raid-map") and has_element?(lv, "#raid-map-near")
    assert render(lv) =~ ~r/Встреча 1 из 1[1-4]/
    assert has_element?(lv, "#raid-world")

    lv |> enter() |> element("#raid-option-0") |> render_click()
    assert has_element?(lv, "#raid-outcome-1")

    lv = finish(lv)
    html = render(lv)

    assert html =~ "Чистый выход" or html =~ "Вышли" or html =~ "Никто не выжил"

    lv |> element("#btn-raid-again") |> render_click()
    assert has_element?(lv, "#raid-event-0") or has_element?(lv, "#raid-moves")
    refute has_element?(lv, ".raid-member-lost")
  end

  test "a late or double click doesn't choose for the next event", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()
    lv |> enter() |> element("#raid-option-0") |> render_click()
    assert has_element?(lv, "#raid-outcome-1")

    # a click made at the first event arrives once the squad has moved on
    render_click(lv, "choose", %{"index" => "0", "turn" => "0"})
    refute has_element?(lv, "#raid-outcome-2")
  end

  test "a reconnect picks its run up again; a fresh visit or another tab doesn't",
       %{conn: conn} do
    conn = init_test_session(conn, %{"user_id" => "raid-#{System.unique_integer()}"})
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()
    run = assert_patch(lv)
    lv |> enter() |> element("#raid-option-0") |> render_click()
    squad = lv |> element("#raid-squad") |> render()

    {:ok, again, _html} = live(conn, run)
    assert has_element?(again, "#raid-outcome-1")
    assert again |> element("#raid-squad") |> render() == squad

    # a fresh visit is the lobby; another tab's raid is a run of its own
    {:ok, fresh, _html} = live(conn, ~p"/raid")
    refute has_element?(fresh, "#raid")
    fresh |> element("#btn-raid-recruit") |> render_click()
    refute assert_patch(fresh) == run

    {:ok, again, _html} = live(conn, run)
    assert again |> element("#raid-squad") |> render() == squad
  end

  test "back and forward go between runs; a new raid forgets the page's old one",
       %{conn: conn} do
    conn = init_test_session(conn, %{"user_id" => "raid-#{System.unique_integer()}"})
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()
    first = assert_patch(lv)

    finish(lv)
    lv |> element("#btn-raid-again") |> render_click()
    second = assert_patch(lv)
    raid = lv |> element("#raid") |> render()

    # the first run is forgotten: back to it is the lobby, forward is the raid again
    render_patch(lv, first)
    refute has_element?(lv, "#raid")
    render_patch(lv, second)
    assert lv |> element("#raid") |> render() == raid
  end

  # the runs a user has in RaidStore (its table holds {{user_id, run}, saved, at})
  defp runs(user_id),
    do: for({{^user_id, run}, _saved, _at} <- :ets.tab2list(RaidStore), do: run)

  test "a raid the address starts forgets nothing: the raid under way is still there",
       %{conn: conn} do
    user_id = "raid-#{System.unique_integer([:positive])}"
    conn = init_test_session(conn, %{"user_id" => user_id})
    link = Raid.path([%{name: "Дед Мороз", rarity: :common}, %{name: "Гена Лена", rarity: :epic}])

    {:ok, lv, _html} = live(conn, link)
    [run] = runs(user_id)
    lv |> element("#raid-option-0") |> render_click()
    raid = lv |> element("#raid") |> render()

    # the link once more, without its run (as the back button used to bring it)
    render_patch(lv, link)
    assert_patch(lv)
    assert run in runs(user_id) and length(runs(user_id)) == 2

    render_patch(lv, link <> "&run=" <> run)
    assert lv |> element("#raid") |> render() == raid
  end

  test "a squad's sets show with the bonus they add, none without", %{conn: conn} do
    # Лена and Арена rhyme
    rhyme = [%{name: "Гена Лена", rarity: :epic}, %{name: "Сеня Арена", rarity: :common}]
    {:ok, lv, _html} = live(conn, Raid.path(rhyme))
    assert lv |> element("#raid-sets") |> render() =~ "Рифма +5"

    {:ok, lv, _html} = live(conn, Raid.path([%{name: "Дед Мороз", rarity: :common}]))
    refute has_element?(lv, "#raid-sets")
  end

  test "a page keeps its last three runs, however many it's made to start", %{conn: conn} do
    user_id = "raid-#{System.unique_integer([:positive])}"
    conn = init_test_session(conn, %{"user_id" => user_id})
    link = Raid.path([%{name: "Дед Мороз", rarity: :common}])
    {:ok, lv, _html} = live(conn, link)

    # what a crafted client may send: a patch to the link, over and over
    for _ <- 1..200 do
      render_patch(lv, link)
      assert_patch(lv)
    end

    assert length(runs(user_id)) == 3
  end

  test "a squad link skips empty names and knows the gnome", %{conn: conn} do
    token = Base.url_encode64("Дед Мороз\n \nГНОМ ГНОМЫЧ", padding: false)
    {:ok, lv, _html} = live(conn, "/raid?team=" <> token)

    assert members(lv) == 2
    assert lv |> element("#raid-member-1") |> render() =~ "gnome-name"
  end

  test "the lobby lets be what it has no raid for", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/raid")

    render_click(lv, "again")
    render_click(lv, "choose", %{"index" => "0", "turn" => "0"})
    render_click(lv, "nope", %{})

    refute has_element?(lv, "#raid")
    assert has_element?(lv, "#btn-raid-recruit")
  end

  test "a raid under way isn't dropped for a new one", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()
    assert_patch(lv)
    raid = lv |> element("#raid") |> render()

    render_click(lv, "again")
    render_click(lv, "recruit")
    assert lv |> element("#raid") |> render() == raid
  end

  test "a squad may leave its raid: the page is back at the lobby, the run is gone",
       %{conn: conn} do
    conn = init_test_session(conn, %{"user_id" => "raid-#{System.unique_integer()}"})
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()
    run = assert_patch(lv)

    lv |> element("#btn-raid-leave") |> render_click()
    assert_patch(lv, ~p"/raid")
    refute has_element?(lv, "#raid")

    {:ok, _again, html} = live(conn, run)
    assert html =~ "Набрать отряд"
  end

  test "takes the squad from the Team page link, rarities worked out again", %{conn: conn} do
    team = [%{name: "Дед Мороз", rarity: :common}, %{name: "Алиса Аврора", rarity: :legendary}]
    {:ok, lv, _html} = live(conn, Raid.path(team))

    assert members(lv) == 2
    assert lv |> element("#raid-member-0") |> render() =~ "legendary-name"
    assert lv |> element("#raid-member-1") |> render() =~ "rare-name"
  end

  test "a broken squad link falls back to recruiting", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/raid?team=%%%")
    assert html =~ "Набрать отряд"
  end

  test "the Team page sends its team on a raid", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/team_scavengers")
    refute has_element?(lv, "#btn-team-raid")

    team = [%{name: "Гена Лена", rarity: :epic}]
    send(lv.pid, {:team_generated, team})

    assert lv |> element("#btn-team-raid") |> render() =~ Raid.path(team)
  end

  test "loot waits in a stash: a button with its count opens a modal with the list" do
    loot = [
      %{item: :rooster, owner: "Гена Лена", alive: true},
      %{item: :ledx, owner: "Дед Мороз", alive: false}
    ]

    html = render_component(&NeuroScavWeb.RaidComponents.stash/1, loot: loot)
    doc = LazyHTML.from_fragment(html)

    # the button counts the loot that works: a fallen finder's doesn't
    button = doc |> LazyHTML.query("#btn-raid-stash") |> LazyHTML.text()
    assert button =~ "Нычка" and button =~ "1"
    assert doc |> LazyHTML.query(".raid-stash-inactive") |> LazyHTML.text() =~ "ЛЕДХ"
    # hidden until the button opens it
    assert doc |> LazyHTML.query("#raid-stash.hidden") |> Enum.count() == 1

    list = doc |> LazyHTML.query(".raid-stash-list li") |> Enum.map(&LazyHTML.text/1)
    assert [rooster, ledx] = list
    assert rooster =~ "Золотой петух" and rooster =~ "+10 Удача" and rooster =~ "Гена Лена"
    assert ledx =~ "ЛЕДХ" and ledx =~ "+5 ко всему" and ledx =~ "Дед Мороз"
    # a finder who didn't make it out is struck out
    assert doc |> LazyHTML.query(".raid-stash-owner-dead") |> LazyHTML.text() =~ "Дед Мороз"
  end

  test "loot that takes a stat shows it with a minus" do
    html =
      render_component(&NeuroScavWeb.RaidComponents.stash/1,
        loot: [%{item: :etg, owner: "Гена Лена", alive: true}]
      )

    assert html =~ "eTG-change"
    assert html =~ "+15 Ловкость"
    assert html =~ "−5 Удача"
  end

  test "every kind of loot is translated in every language" do
    for locale <- ~w(ru en de ja), item <- NeuroScav.Raid.loot() do
      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        msgid = "Item #{item}"

        assert Gettext.gettext(NeuroScavWeb.Gettext, msgid, list: "X") != msgid,
               "#{locale}: #{msgid}"
      end)
    end
  end

  test "the stash button is there from the start; an empty stash says so", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()

    assert lv |> element(".raid-squad-row #btn-raid-stash") |> render() =~ "0"
    assert lv |> element("#raid-stash") |> render() =~ "Пусто"
  end

  test "every event and option is translated in every language" do
    squad = [%{name: "Алиса Аврора", rarity: :common}]

    for locale <- ~w(ru en de ja), event <- NeuroScav.Raid.events() do
      # an option is named by its rest, the stat it checks, the item it needs or its condition
      labels =
        for option <- NeuroScav.Raid.options(NeuroScav.Raid.new(squad, [event])),
            label =
              option.camp || option.stat || option.key || (option.pay && :pay) ||
                (option.trust && :karma),
            label != nil,
            do: label

      msgids = ["Raid #{event}", "Raid #{event} text"] ++ Enum.map(labels, &"Raid #{event} #{&1}")

      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        for msgid <- msgids,
            do:
              assert(Gettext.gettext(NeuroScavWeb.Gettext, msgid) != msgid, "#{locale}: #{msgid}")
      end)
    end
  end

  test "every way a death is told is translated in every language" do
    for locale <- ~w(ru en de ja), n <- 1..19 do
      msgid = "Raid death #{n} %{name}"

      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        told = Gettext.gettext(NeuroScavWeb.Gettext, msgid, name: "X")
        assert told != "Raid death #{n} X" and told =~ "X", "#{locale}: #{msgid}"
      end)
    end
  end

  test "the legend and every icon's meaning are translated in every language" do
    msgids =
      ["Raid legend", "Raid icon train %{value}", "Raid icon wound %{value}"] ++
        ["Raid icon retreat %{limit}"] ++
        Enum.map(~w(loot revive promote trophy lose drop stall), &"Raid icon #{&1}")

    for locale <- ~w(ru en de ja), msgid <- msgids do
      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        told = Gettext.gettext(NeuroScavWeb.Gettext, msgid, value: 10, limit: 2)
        refute told =~ "Raid ", "#{locale}: #{msgid}"
      end)
    end
  end

  test "the map's words are translated in every language" do
    msgids =
      ["Raid map", "Raid map about", "Raid way start", "Raid way next", "Raid exited %{exit}"] ++
        ["Raid node deadly", "Raid needs payment", "Raid needs karma %{value}", "Raid trusted"] ++
        ["Raid paid %{name} %{item}", "Raid your move"] ++
        Enum.map(
          ~w(boss exit fight loot search scav gnome rare hazard hidden),
          &"Raid node #{&1}"
        ) ++
        Enum.map(NeuroScav.Raid.locations(), &"Raid location #{&1}") ++
        Enum.map(~w(common uncommon rare epic legendary gnome), &"Raid rarity #{&1}")

    for locale <- ~w(ru en de ja), msgid <- msgids do
      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        told =
          Gettext.gettext(NeuroScavWeb.Gettext, msgid, exit: "X", value: 1, name: "Y", item: "Z")

        refute told =~ "Raid ",
               "#{locale}: #{msgid}"
      end)
    end
  end

  test "every weather and every time of day is translated in every language" do
    catalog = Catalog.compiled()

    msgids =
      Enum.map(Map.keys(catalog.weathers), &"Raid weather #{&1}") ++
        Enum.map(Keyword.keys(catalog.daytimes), &"Raid daytime #{&1}") ++
        Enum.map(~w(fight search hide strength agility luck), &"Raid kind #{&1}") ++
        ["Raid easier %{list}", "Raid harder %{list}"]

    for locale <- ~w(ru en de ja), msgid <- msgids do
      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        assert Gettext.gettext(NeuroScavWeb.Gettext, msgid, list: "X") != msgid,
               "#{locale}: #{msgid}"
      end)
    end
  end

  test "every trait, what it does and the search are translated in every language" do
    msgids =
      ["Raid traits", "Raid search", "Raid search again", "Raid search leave", "Raid left"] ++
        ["Raid found %{name} %{item}", "Raid caught %{name} %{stat} %{value}"] ++
        Enum.flat_map(NeuroScav.Raid.traits(), &["Raid trait #{&1}", "Raid trait #{&1} about"]) ++
        Enum.map(~w(greedy psycho coward chatty chatty_scav lucky), &"Raid quirk #{&1} %{name}")

    for locale <- ~w(ru en de ja), msgid <- msgids do
      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        told =
          Gettext.gettext(NeuroScavWeb.Gettext, msgid, name: "X", item: "Y", stat: "Z", value: 1)

        refute told =~ "Raid ", "#{locale}: #{msgid}"
      end)
    end
  end

  test "a member's card shows the stats with their loot and the bonus beside" do
    card = NeuroScav.BattleRoom.card(%{name: "Гена Лена", rarity: :epic})

    html =
      render_component(&NeuroScavWeb.CoreComponents.card_stats/1,
        card: card,
        bonus: %{strength: 10, agility: -5}
      )

    strength = html |> LazyHTML.from_fragment() |> LazyHTML.query(~s([data-stat="strength"]))
    assert LazyHTML.text(strength) =~ "#{card.stats.strength + 10}"
    assert strength |> LazyHTML.query(".stat-bonus-up") |> LazyHTML.text() =~ "+10"

    agility = html |> LazyHTML.from_fragment() |> LazyHTML.query(~s([data-stat="agility"]))
    assert LazyHTML.text(agility) =~ "#{card.stats.agility - 5}"
    assert agility |> LazyHTML.query(".stat-bonus-down") |> LazyHTML.text() =~ "−5"

    # no bonus, no marker
    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query(~s([data-stat="luck"] .stat-bonus))
           |> Enum.count() == 0
  end

  describe "a raid along a route of the test's own" do
    # the raid is put in RaidStore and the page comes to its run, as a reconnect would
    defp raid_page(conn, route, play \\ & &1) do
      user_id = "raid-#{System.unique_integer([:positive])}"

      members =
        Enum.map(["Алиса Аврора", "Гена Лена", "Дед Мороз"], &ScavengersServer.check_name/1)

      raid = members |> NeuroScav.Raid.new(route) |> play.()
      RaidStore.put({user_id, "test"}, members, raid)

      {:ok, lv, _html} =
        conn |> init_test_session(%{"user_id" => user_id}) |> live(~p"/raid?run=test")

      {lv, raid}
    end

    defp ru(msgid, bindings \\ %{}),
      do:
        Gettext.with_locale(NeuroScavWeb.Gettext, "ru", fn ->
          Gettext.gettext(NeuroScavWeb.Gettext, msgid, bindings)
        end)

    # the raid a step on, the step having done `changes`: the page tells it
    defp told(conn, changes) do
      last = %{
        event: :pmc,
        outcome: :pass,
        member: "Гена Лена",
        index: 1,
        item: nil,
        stat: :strength,
        retreat: false,
        follow_up: nil,
        karma: 0,
        used: nil,
        quirk: nil,
        roll: nil,
        chance: nil
      }

      {lv, _raid} =
        raid_page(
          conn,
          [:pmc, :office],
          &%{NeuroScav.Raid.choose(&1, 1, 1) | last: Map.merge(last, changes)}
        )

      lv |> element("#raid-outcome-1") |> render()
    end

    test "the outcome keeps its box from the first choice on, a long one in a smaller font",
         %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:office, :pmc])

      assert lv |> element("#raid-outcome-box #raid-outcome-none") |> render() =~
               ru("Raid your move")

      lv |> element("#raid-option-1") |> render_click()
      assert has_element?(lv, "#raid-outcome-box #raid-outcome-1")
      refute has_element?(lv, "#raid-outcome-none")

      refute told(conn, %{}) =~ "raid-outcome-long"

      long = %{
        outcome: :loot,
        item: :sj6,
        quirk: {:greedy, "Гена Лена"},
        follow_up: :ambush,
        karma: -1
      }

      assert told(conn, long) =~ "raid-outcome-long"
    end

    test "a check shows its roll against the chance, a check by each the roll alone",
         %{conn: conn} do
      # the stairs: no loot nor fight, so nobody takes over the safe option
      {lv, _raid} = raid_page(conn, [:stairs, :stairs, :pmc])
      lv |> element("#raid-option-1") |> render_click()
      refute has_element?(lv, "#raid-roll")
      lv |> element("#raid-option-0") |> render_click()
      assert has_element?(lv, "#raid-roll")

      roll = fn changes ->
        told(conn, changes) |> LazyHTML.from_fragment() |> LazyHTML.query("#raid-roll")
      end

      assert roll.(%{roll: 34, chance: 41}) |> LazyHTML.text() =~ "34 ≤ 41"
      assert roll.(%{roll: 60, chance: 41}) |> LazyHTML.text() =~ "60 > 41"
      assert roll.(%{roll: 34}) |> LazyHTML.text() |> String.trim() == "34"
      assert render(lv) =~ ru("Raid roll tip")
    end

    test "a camp offers its three rests, each telling who it's for or why it can't be had",
         %{conn: conn} do
      {lv, raid} = raid_page(conn, [:camp, :pmc])
      html = lv |> element("#raid-event-0") |> render()

      for msgid <-
            ["Raid camp heal", "Raid camp nobody wounded", "Raid camp train"] ++
              ["Raid camp repack", "Raid camp nothing to repack"],
          do: assert(html =~ ru(msgid), msgid)

      %{member: trainee, stat: stat} = Enum.at(NeuroScav.Raid.options(raid), 1)
      assert html =~ "#{trainee.name} · #{ru("Stat #{stat}")} +10"

      lv |> element("#raid-option-1") |> render_click()

      assert lv |> element("#raid-outcome-1") |> render() =~
               ru("Raid train %{name} %{stat} %{value}",
                 name: trainee.name,
                 stat: ru("Stat #{stat}"),
                 value: 10
               )
    end

    test "every outcome is told in words of its own", %{conn: conn} do
      name = "Гена Лена"
      strength = ru("Stat strength")
      sj6 = ru("Item sj6")

      for {changes, words} <- [
            {%{outcome: :safe}, ru("Raid passed")},
            {%{outcome: :pass}, ru("Raid success %{name}", name: name)},
            {%{outcome: :nothing}, ru("Raid nothing %{name}", name: name)},
            {%{outcome: :revive}, ru("Raid revive %{name}", name: name)},
            {%{outcome: :train},
             ru("Raid train %{name} %{stat} %{value}", name: name, stat: strength, value: 10)},
            {%{outcome: :wound},
             ru("Raid wound %{name} %{stat} %{value}", name: name, stat: strength, value: 10)},
            {%{outcome: :promote}, ru("Raid promote %{name}", name: name)},
            {%{outcome: :stall}, ru("Raid stall %{name}", name: name)},
            {%{outcome: :drop}, ru("Raid drop nothing %{name}", name: name)},
            {%{outcome: :drop, item: :sj6},
             ru("Raid drop %{name} %{item}", name: name, item: sj6)},
            {%{event: :gnome_thief, outcome: :drop}, ru("Raid gnome stole nothing")},
            {%{event: :gnome_thief, outcome: :drop, item: :sj6},
             ru("Raid gnome stole %{item}", item: sj6)},
            {%{outcome: :loot, item: :sj6}, ru("Raid loot %{item}", item: sj6)},
            {%{event: :kaban, outcome: :trophy, item: :pkm},
             ru("Raid trophy %{name} %{item}", name: name, item: ru("Item pkm"))},
            {%{follow_up: :ambush}, ru("Raid follow up")},
            {%{karma: -1}, ru("Raid karma down")},
            {%{event: :mines, outcome: :pass, member: nil}, ru("Raid all passed")},
            {%{outcome: :wounds, member: "Алиса Аврора, Гена Лена"},
             ru("Raid wounds %{names} %{stat} %{value}",
               names: "Алиса Аврора, Гена Лена",
               stat: strength,
               value: 10
             )},
            {%{outcome: :heal}, ru("Raid heal %{name}", name: name)},
            {%{outcome: :spared, used: :propital},
             ru("Raid spared %{name} %{item}", name: name, item: ru("Item propital"))},
            {%{outcome: :wound, used: :medkit}, ru("Raid used %{item}", item: ru("Item medkit"))},
            {%{event: :labs, outcome: :loot, item: :sj6, used: :keycard},
             ru("Raid used %{item}", item: ru("Item keycard"))},
            {%{event: :abandoned_store, outcome: :found, stat: :luck, item: :sj6},
             ru("Raid found %{name} %{item}", name: name, item: sj6)},
            {%{event: :abandoned_store, outcome: :left, member: nil, stat: nil}, ru("Raid left")},
            {%{event: :abandoned_store, outcome: :wound, stat: :luck},
             ru("Raid caught %{name} %{stat} %{value}",
               name: name,
               stat: ru("Stat luck"),
               value: 10
             )},
            {%{event: :office, outcome: :loot, item: :sj6, quirk: {:greedy, name}},
             ru("Raid quirk greedy %{name}", name: name)},
            {%{outcome: :pass, quirk: {:chatty_scav, "Дед Мороз"}},
             ru("Raid quirk chatty_scav %{name}", name: "Дед Мороз")},
            {%{event: :camp, outcome: :repacked, member: nil, stat: nil}, ru("Raid repacked")}
          ] do
        assert told(conn, changes) =~ words, inspect(changes)
      end
    end

    # every way a death is told, in Russian
    defp deaths(name) do
      [ru("Raid lost %{name}", name: name)] ++
        for n <- 1..19, do: ru("Raid death #{n} %{name}", name: name)
    end

    test "a death is told one of twenty ways, the same one at every render", %{conn: conn} do
      text = fn name, event ->
        told(conn, %{outcome: :lose, member: name, event: event})
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()
        |> String.trim()
      end

      told = text.("Гена Лена", :pmc)
      assert Enum.any?(deaths("Гена Лена"), &String.starts_with?(told, &1))
      assert text.("Гена Лена", :pmc) == told

      told_ways =
        for event <- [:pmc, :sniper, :mines, :killa, :tagilla, :goons, :labs, :bait],
            do: text.("Гена Лена", event)

      assert told_ways |> Enum.uniq() |> length() > 3
    end

    test "the world is told in a line: the conditions, then the checks they ease and harden",
         %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:pmc], &%{&1 | weather: :fog, daytime_start: 3})
      world = lv |> element("#raid-world") |> render()

      assert world =~ ru("Raid daytime night") and world =~ ru("Raid weather fog")
      # the night: hiding +10, fights and searches −5; fog: agility +5, strength −10
      assert world =~ "легче: прятаться, ловкость; тяжелее: драться, искать, сила"
      refute world =~ "+" or world =~ "−"

      {lv, _raid} = raid_page(conn, [:pmc], &%{&1 | weather: :clear, daytime_start: 0})
      world = lv |> element("#raid-world") |> render()
      assert world =~ ru("Raid daytime morning") and world =~ ru("Raid weather clear")
      assert world =~ "#tabler-sunrise" and world =~ "#tabler-sun\""
      assert world =~ "— легче: искать"
      refute world =~ "тяжелее"
    end

    test "a member's card names their rarity as one member's", %{conn: conn} do
      {lv, raid} = raid_page(conn, [:pmc])
      member = Enum.at(raid.squad, 1)

      card = lv |> element("#raid-member-1 .battle-card-rarity") |> render()
      assert card =~ ru("Raid rarity #{member.rarity}")
      assert ru("Raid rarity common") == "Обычный"
    end

    test "a member's trait shows on the card, all of them in the legend", %{conn: conn} do
      {lv, raid} = raid_page(conn, [:pmc])
      member = Enum.at(raid.squad, 1)
      tip = ru("Raid trait #{member.trait}") <> ": " <> ru("Raid trait #{member.trait} about")

      assert has_element?(lv, ~s(#raid-member-trait-1[data-tip="#{tip}"]))
      legend = lv |> element("#raid-legend-traits") |> render()
      for trait <- NeuroScav.Raid.traits(), do: assert(legend =~ ru("Raid trait #{trait}"))
    end

    test "a search offers one more look, riskier every time, or leaving", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:abandoned_store, :pmc])
      search = lv |> element("#raid-option-0") |> render()
      assert search =~ ru("Raid search") and search =~ "%"
      assert lv |> element("#raid-option-1") |> render() =~ ru("Raid search leave")

      {lv, _raid} =
        raid_page(conn, [:abandoned_store, :pmc], &NeuroScav.Raid.choose(&1, 0, 1, :sj6))

      assert lv |> element("#raid-option-0") |> render() =~ ru("Raid search again")
      assert lv |> element("#raid-event-1 .wheel-panel-header") |> render() =~ "Встреча 1 из 2"
      assert lv |> element("#raid-outcome-1") |> render() =~ ru("Item sj6")
    end

    test "a key shows what it needs, and who'd use it", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:labs])
      assert lv |> element("#raid-option-2[disabled]") |> render() =~ ru("Item keycard")

      {lv, _raid} = raid_page(conn, [:labs], &%{&1 | stash: [%{item: :keycard, owner: 0}]})
      key = lv |> element("#raid-option-2") |> render()
      refute key =~ "disabled"
      assert key =~ "#tabler-key" and key =~ "Алиса Аврора"
    end

    test "a check tells who makes it: the weakest, or everyone", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:footsteps])
      assert lv |> element("#raid-option-1") |> render() =~ "слабейший:"

      {lv, _raid} = raid_page(conn, [:mines])
      assert lv |> element("#raid-option-0") |> render() =~ ru("Raid check each")
    end

    test "a member's wounds show on their card, a bleeding too", %{conn: conn} do
      {lv, _raid} =
        raid_page(conn, [:pmc], fn raid ->
          put_in(raid.squad, List.update_at(raid.squad, 0, &%{&1 | wounds: 2}))
        end)

      wounds = lv |> element("#raid-member-wounds-0") |> render()
      assert wounds =~ ~r/#tabler-droplet.*2/s and wounds =~ ru("Raid bleeding")
      refute has_element?(lv, "#raid-member-wounds-1")
    end

    test "the end tells how many made it out", %{conn: conn} do
      verdict = fn route, play ->
        {lv, _raid} = raid_page(conn, route, play)
        lv |> element("#raid-end") |> render()
      end

      assert verdict.([:office], &NeuroScav.Raid.choose(&1, 1, 1)) =~ ru("Raid clean")

      assert verdict.([:pmc], &NeuroScav.Raid.choose(&1, 0, 100)) =~
               ru("Raid survived %{alive} %{total}", alive: 2, total: 3)

      wiped = fn raid -> %{raid | squad: Enum.map(raid.squad, &%{&1 | alive: false})} end
      assert verdict.([:pmc], wiped) =~ ru("Raid failed")
    end

    test "a stall keeps the encounter's number, the event is another one", %{conn: conn} do
      {lv, _raid} =
        raid_page(conn, [:desync, :pmc], fn raid ->
          %{raid | spares: [:office]} |> NeuroScav.Raid.choose(1, 100)
        end)

      assert lv |> element("#raid-outcome-1") |> render() =~ "не прошёл"
      header = lv |> element("#raid-event-1 .wheel-panel-header") |> render()
      assert header =~ ru("Raid office")
      assert header =~ "Встреча 1 из 2"

      # a click made before the stall, at the same encounter, meant the event that's gone
      render_click(lv, "choose", %{"index" => "0", "turn" => "0"})
      refute has_element?(lv, "#raid-outcome-2")
    end

    test "the legend sits behind a button, in a modal; an icon tells its meaning on hover",
         %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:bait])

      assert has_element?(lv, "#raid-event-0 .wheel-panel-header #btn-raid-legend")
      refute has_element?(lv, ".raid-legend")

      legend = lv |> element("#raid-legend.hidden") |> render()

      for meaning <- [
            ru("Raid icon loot"),
            ru("Raid icon lose"),
            ru("Raid icon stall"),
            ru("Raid icon train %{value}", value: 10),
            ru("Raid icon retreat %{limit}", limit: NeuroScav.Raid.retreat_limit())
          ],
          do: assert(legend =~ meaning)

      map = lv |> element("#raid-legend-map") |> render()
      assert map =~ ru("Raid node boss") and map =~ ru("Raid node hidden")
      assert map =~ ru("Raid map about")

      # the bait: an agility check for loot that may kill, or the safe way, a retreat
      assert has_element?(lv, ~s(#raid-option-0 .raid-icon[data-tip="#{ru("Raid icon loot")}"]))
      assert has_element?(lv, ~s(#raid-option-0 .raid-icon[data-tip="#{ru("Raid icon lose")}"]))

      assert has_element?(
               lv,
               ~s(#raid-option-1 .raid-icon[data-tip="#{ru("Raid icon retreat %{limit}", limit: NeuroScav.Raid.retreat_limit())}"])
             )
    end

    test "a boss stands out in red", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:kaban, :pmc])

      assert has_element?(lv, "#raid-event-0.raid-event-boss")

      assert lv |> element("#raid-event-0 .wheel-panel-header") |> render() =~
               ~r/#tabler-skull.*Кабан/s
    end

    test "after a retreat the retreats are locked, the rest isn't", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:office, :axeman], &NeuroScav.Raid.choose(&1, 1, 1))

      assert has_element?(lv, "#raid-option-1[disabled]")
      assert lv |> element("#raid-option-1") |> render() =~ "Хватит отступать"
      refute has_element?(lv, "#raid-option-0[disabled]")
      assert render(lv) =~ "подряд можно не больше 1"

      # a locked retreat sent anyway changes nothing
      render_click(lv, "choose", %{"index" => "1", "turn" => "1"})
      refute has_element?(lv, "#raid-outcome-2")
    end

    test "the map shows where the squad is; where the way forks it picks, on the map too",
         %{conn: conn} do
      fork = %{
        nodes: %{{0, 0} => :office, {1, 0} => :pmc, {1, 1} => :bait, {2, 0} => :exit_car},
        links: %{{0, 0} => [{1, 0}, {1, 1}], {1, 0} => [{2, 0}], {1, 1} => [{2, 0}], {2, 0} => []}
      }

      {lv, _raid} = raid_page(conn, fork)
      assert has_element?(lv, ~s(#raid-map [data-node="0-0"].raid-node-at))
      assert lv |> element(~s(#raid-map [data-node="2-0"])) |> render() =~ ru("Raid exit_car")

      # whatever comes of the office, the way forks after it
      lv |> element("#raid-option-1") |> render_click()
      assert lv |> element("#raid-moves .wheel-panel-header") |> render() =~ ru("Raid way next")
      assert lv |> element("#raid-option-0") |> render() =~ ru("Raid pmc")
      assert lv |> element("#raid-option-1") |> render() =~ ru("Raid bait")
      assert has_element?(lv, ~s(#raid-map [data-node="1-1"].raid-node-next))
      # both ways may cost a member
      assert lv |> element("#raid-option-1") |> render() =~ "#tabler-skull"

      lv |> element(~s(#raid-map [data-node="1-1"])) |> render_click()
      assert lv |> element("#raid-event-1 .wheel-panel-header") |> render() =~ ru("Raid bait")
      assert has_element?(lv, "#raid-map path.raid-link-taken")

      # a late click on the other way, or one naming no node, changes nothing
      render_click(lv, "move", %{"node" => "1-0"})
      render_click(lv, "move", %{"node" => "x"})
      assert lv |> element("#raid-event-1 .wheel-panel-header") |> render() =~ ru("Raid bait")
    end

    test "a phone has a strip of the map round the squad, the whole of it in a dialog",
         %{conn: conn} do
      route = [:office, :pmc, :trunk, :bait, :medic, :toll, :exit_car]
      {lv, _raid} = raid_page(conn, route)

      # the strip: five layers from where the squad is; the card and the dialog: all of them
      assert has_element?(lv, ~s(#raid-map-near [data-node="4-0"]))
      refute has_element?(lv, ~s(#raid-map-near [data-node="5-0"]))
      assert has_element?(lv, ~s(#raid-map [data-node="6-0"]))
      assert has_element?(lv, ~s(#raid-map-dialog.hidden #raid-map-full [data-node="6-0"]))
      assert has_element?(lv, "#btn-raid-map")

      # the icons are symbols on the page, the nodes use them
      assert has_element?(lv, "symbol#tabler-door-exit")
    end

    test "a move from the dialog's map takes the squad there", %{conn: conn} do
      fork = %{
        nodes: %{{0, 0} => :office, {1, 0} => :pmc, {1, 1} => :bait, {2, 0} => :exit_car},
        links: %{{0, 0} => [{1, 0}, {1, 1}], {1, 0} => [{2, 0}], {1, 1} => [{2, 0}], {2, 0} => []}
      }

      {lv, _raid} = raid_page(conn, fork)
      lv |> element("#raid-option-1") |> render_click()
      lv |> element(~s(#raid-map-full [data-node="1-0"])) |> render_click()

      assert lv |> element("#raid-event-1 .wheel-panel-header") |> render() =~ ru("Raid pmc")
    end

    test "with several ways in, the raid starts with picking one", %{conn: conn} do
      starts = %{
        nodes: %{{0, 0} => :office, {0, 2} => :pmc, {1, 1} => :exit_boat},
        links: %{{0, 0} => [{1, 1}], {0, 2} => [{1, 1}], {1, 1} => []}
      }

      {lv, _raid} = raid_page(conn, starts)
      assert lv |> element("#raid-moves .wheel-panel-header") |> render() =~ ru("Raid way start")

      lv |> element("#raid-option-1") |> render_click()
      assert lv |> element("#raid-event-0 .wheel-panel-header") |> render() =~ ru("Raid pmc")
    end

    test "the car takes the stash's last item for the way out; with nothing to pay it's locked",
         %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:exit_car])
      assert lv |> element("#raid-option-0[disabled]") |> render() =~ ru("Raid needs payment")

      {lv, _raid} = raid_page(conn, [:exit_car], &%{&1 | stash: [%{item: :sj6, owner: 0}]})
      pay = lv |> element("#raid-option-0") |> render()
      assert pay =~ ru("Raid exit_car pay") and pay =~ ru("Item sj6") and pay =~ "Алиса Аврора"

      lv |> element("#raid-option-0") |> render_click()

      assert lv |> element("#raid-outcome-1") |> render() =~
               ru("Raid paid %{name} %{item}", name: "Алиса Аврора", item: ru("Item sj6"))

      assert has_element?(lv, "#raid-exit")
    end

    test "the co-op exit is open to a squad the scavs like", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:exit_coop])

      assert lv |> element("#raid-option-0[disabled]") |> render() =~
               ru("Raid needs karma %{value}", value: 1)

      {lv, _raid} = raid_page(conn, [:exit_coop], &%{&1 | karma: 2})
      assert lv |> element("#raid-option-0") |> render() =~ ru("Raid exit_coop karma")

      lv |> element("#raid-option-0") |> render_click()
      assert lv |> element("#raid-outcome-1") |> render() =~ ru("Raid trusted")
    end

    test "a red ring marks where a member may be lost", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:office, :pmc, :trunk])

      assert lv |> element(~s(#raid-map [data-node="1-0"].raid-node-deadly)) |> render() =~
               ru("Raid icon lose")

      refute has_element?(lv, ~s(#raid-map [data-node="2-0"].raid-node-deadly))
      assert lv |> element("#raid-legend-map") |> render() =~ ru("Raid node deadly")
    end

    test "through an exit the raid is over, the end tells which", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:exit_car])
      lv |> element("#raid-option-1") |> render_click()

      assert lv |> element("#raid-end #raid-exit") |> render() =~
               ru("Raid exited %{exit}", exit: ru("Raid exit_car"))

      # who made it out, what they carried out, and a link to tell it
      assert lv |> element("#raid-result-squad") |> render() =~ "Гена Лена"
      assert lv |> element("#raid-result-loot") |> render() =~ ru("Raid result no loot")
      assert has_element?(lv, ~s(#raid-end button[data-url^="/share/raid/"]))
    end

    test "at night the map hides what's far off and unseen, but not a boss or the exits",
         %{conn: conn} do
      route = [:office, :pmc, :trunk, :kaban, :exit_car]
      night = &%{&1 | weather: :clear, daytime_start: 3, seen: MapSet.new()}
      {lv, _raid} = raid_page(conn, route, night)

      assert lv |> element(~s(#raid-map [data-node="1-0"])) |> render() =~ ru("Raid pmc")
      assert has_element?(lv, ~s(#raid-map [data-node="2-0"].raid-node-hidden))

      assert lv |> element(~s(#raid-map [data-node="3-0"].raid-node-boss)) |> render() =~
               "#tabler-skull"

      assert lv |> element(~s(#raid-map [data-node="4-0"])) |> render() =~ ru("Raid exit_car")
      assert has_element?(lv, ".raid-board-dark .raid-map-note", ru("Raid map night"))

      # what the squad saw before it remembers, pale
      {lv, _raid} =
        raid_page(conn, route, &%{night.(&1) | seen: MapSet.new(Map.keys(&1.map.nodes))})

      assert has_element?(lv, ~s(#raid-map [data-node="2-0"].raid-node-remembered))
    end

    test "a map's location: its name by the world and on the card, its tint", %{conn: conn} do
      {lv, _raid} = raid_page(conn, NeuroScav.Raid.random_map(:woods))
      woods = ru("Raid location woods")

      assert lv |> element("#raid-world") |> render() =~ woods
      assert has_element?(lv, ".raid-board-map.raid-location-woods .raid-map-location", woods)
      assert has_element?(lv, "#raid-map-dialog .raid-map-dialog.raid-location-woods", woods)
    end

    test "a branch out of the squad's reach goes pale", %{conn: conn} do
      fork = %{
        nodes: %{{0, 0} => :office, {1, 0} => :pmc, {1, 1} => :bait, {2, 0} => :exit_car},
        links: %{{0, 0} => [{1, 0}, {1, 1}], {1, 0} => [{2, 0}], {1, 1} => [{2, 0}], {2, 0} => []}
      }

      {lv, _raid} =
        raid_page(conn, fork, fn raid ->
          raid |> NeuroScav.Raid.choose(1, 1) |> NeuroScav.Raid.move({1, 1})
        end)

      assert has_element?(lv, ~s(#raid-map [data-node="1-0"].raid-node-gone))
      refute has_element?(lv, ~s(#raid-map [data-node="2-0"].raid-node-gone))
      assert has_element?(lv, "#raid-map path.raid-link-gone")
    end

    test "the squad's node counts down who's on its trail, the card tells who", %{conn: conn} do
      {lv, _raid} =
        raid_page(conn, [:reshala, :pmc, :office, :medic], &NeuroScav.Raid.choose(&1, 0, 1, :sj6))

      assert has_element?(lv, ~s(#raid-map [data-node="1-0"][data-chase="1"]))

      assert has_element?(
               lv,
               ".raid-board-map .raid-map-chase",
               ru("Raid chase %{event} %{n}", event: ru("Raid reshala_guards"), n: 1)
             )
    end

    test "on a phone a tap on a node tells its name", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:office, :pmc, :trunk])

      tap = lv |> element(~s(#raid-map-near [data-node="2-0"])) |> render()
      assert tap =~ "data-text" and tap =~ "#raid-strip-info"
      assert has_element?(lv, "#raid-strip-info")
      assert lv |> element(~s(#raid-map-full [data-node="2-0"])) |> render() =~ "#raid-map-info"
    end

    test "karma shows at the scavs' events only, and in the outcome", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:pmc])
      refute has_element?(lv, "#raid-karma")

      {lv, _raid} = raid_page(conn, [:wounded, :toll])
      assert lv |> element("#raid-event-0 #raid-karma") |> render() =~ "Карма у диких: 0"

      # helping a scav counts whatever the roll; the next event is the scavs' too
      lv |> element("#raid-option-0") |> render_click()
      assert lv |> element("#raid-event-1 #raid-karma.raid-karma-good") |> render() =~ "+1"
      assert lv |> element("#raid-outcome-1") |> render() =~ "Дикие это запомнят."
    end

    test "a boss's trophy is gold in the stash", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:kaban, :pmc], &NeuroScav.Raid.choose(&1, 0, 1))

      assert lv |> element("#raid-stash .raid-stash-trophy") |> render() =~ "ПКМ Кабана"
    end
  end
end
