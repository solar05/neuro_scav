defmodule NeuroScavWeb.RaidLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

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
    assert has_element?(lv, "#raid-event-0")
    assert render(lv) =~ ~r/Встреча 1 из 1[0-3]/
    assert lv |> element("#raid-karma") |> render() =~ "Карма у диких: 0"

    lv |> element("#raid-option-0") |> render_click()
    assert has_element?(lv, "#raid-outcome-1")

    lv = finish(lv)
    html = render(lv)

    assert html =~ "Чистый выход" or html =~ "Вышли" or html =~ "Никто не выжил"

    lv |> element("#btn-raid-again") |> render_click()
    assert has_element?(lv, "#raid-event-0")
    refute has_element?(lv, ".raid-member-lost")
  end

  test "a late or double click doesn't choose for the next event", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()
    lv |> element("#raid-option-0") |> render_click()
    assert has_element?(lv, "#raid-outcome-1")

    # a click made at the first event arrives once the squad has moved on
    render_click(lv, "choose", %{"index" => "0", "step" => "0"})
    refute has_element?(lv, "#raid-outcome-2")
  end

  test "a reconnect picks its run up again; a fresh visit or another tab doesn't",
       %{conn: conn} do
    conn = init_test_session(conn, %{"user_id" => "raid-#{System.unique_integer()}"})
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()
    run = assert_patch(lv)
    lv |> element("#raid-option-0") |> render_click()
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

    html = render_component(&Raid.stash/1, loot: loot)
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
    html = render_component(&Raid.stash/1, loot: [%{item: :etg, owner: "Гена Лена", alive: true}])
    assert html =~ "eTG-change"
    assert html =~ "+15 Ловкость"
    assert html =~ "−5 Удача"
  end

  test "every kind of loot is translated in every language" do
    for locale <- ~w(ru en de ja), item <- NeuroScav.Raid.loot() do
      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        msgid = "Item #{item}"
        assert Gettext.gettext(NeuroScavWeb.Gettext, msgid) != msgid, "#{locale}: #{msgid}"
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
      stats =
        for %{stat: stat} when stat != nil <-
              NeuroScav.Raid.options(NeuroScav.Raid.new(squad, [event])),
            do: stat

      msgids = ["Raid #{event}", "Raid #{event} text"] ++ Enum.map(stats, &"Raid #{event} #{&1}")

      Gettext.with_locale(NeuroScavWeb.Gettext, locale, fn ->
        for msgid <- msgids,
            do:
              assert(Gettext.gettext(NeuroScavWeb.Gettext, msgid) != msgid, "#{locale}: #{msgid}")
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

    defp ru(msgid),
      do:
        Gettext.with_locale(NeuroScavWeb.Gettext, "ru", fn ->
          Gettext.gettext(NeuroScavWeb.Gettext, msgid)
        end)

    test "a boss stands out in red", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:kaban, :pmc])

      assert has_element?(lv, "#raid-event-0.raid-event-boss")
      assert lv |> element("#raid-event-0 .wheel-panel-header") |> render() =~ "☠ Кабан"
    end

    test "after two retreats in a row the retreats are locked, the rest isn't", %{conn: conn} do
      {lv, _raid} =
        raid_page(conn, [:office, :office, :axeman], fn raid ->
          raid |> NeuroScav.Raid.choose(1, 1) |> NeuroScav.Raid.choose(1, 1)
        end)

      assert has_element?(lv, "#raid-option-1[disabled]")
      assert lv |> element("#raid-option-1") |> render() =~ "Хватит отступать"
      refute has_element?(lv, "#raid-option-0[disabled]")
      assert render(lv) =~ "подряд можно не больше 2"

      # a locked retreat sent anyway changes nothing
      render_click(lv, "choose", %{"index" => "1", "step" => "2"})
      refute has_element?(lv, "#raid-outcome-3")
    end

    test "a crossroads shows where each path leads; the one taken comes next", %{conn: conn} do
      {lv, raid} = raid_page(conn, [:fork_road, :pmc])
      [first, second] = raid.forks.fork_road

      assert lv |> element("#raid-option-0") |> render() =~ "→ " <> ru("Raid #{first}")
      assert lv |> element("#raid-option-1") |> render() =~ "→ " <> ru("Raid #{second}")

      lv |> element("#raid-option-1") |> render_click()
      assert lv |> element("#raid-outcome-1") |> render() =~ "Отряд свернул"

      assert lv |> element("#raid-event-1 .wheel-panel-header") |> render() =~
               ru("Raid #{second}")
    end

    test "karma shows under the route and in the outcome", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:wounded, :pmc])
      assert lv |> element("#raid-karma") |> render() =~ "Карма у диких: 0"

      # helping a scav counts whatever the roll
      lv |> element("#raid-option-0") |> render_click()
      assert lv |> element("#raid-karma.raid-karma-good") |> render() =~ "+1"
      assert lv |> element("#raid-outcome-1") |> render() =~ "Дикие это запомнят."
    end

    test "a boss's trophy is gold in the stash", %{conn: conn} do
      {lv, _raid} = raid_page(conn, [:kaban, :pmc], &NeuroScav.Raid.choose(&1, 0, 1))

      assert lv |> element("#raid-stash .raid-stash-trophy") |> render() =~ "ПКМ Кабана"
    end
  end
end
