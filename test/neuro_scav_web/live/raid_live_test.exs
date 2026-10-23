defmodule NeuroScavWeb.RaidLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

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

  test "a reconnect picks the raid in progress up again, a finished one it doesn't",
       %{conn: conn} do
    conn = init_test_session(conn, %{"user_id" => "raid-#{System.unique_integer()}"})
    {:ok, lv, _html} = live(conn, ~p"/raid")
    lv |> element("#btn-raid-recruit") |> render_click()
    lv |> element("#raid-option-0") |> render_click()
    squad = lv |> element("#raid-squad") |> render()

    {:ok, again, _html} = live(conn, ~p"/raid")
    assert has_element?(again, "#raid-outcome-1")
    assert again |> element("#raid-squad") |> render() == squad

    finish(again)
    {:ok, _fresh, html} = live(conn, ~p"/raid")
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
end
