defmodule NeuroScavWeb.QuizLiveTest do
  use NeuroScavWeb.ConnCase

  import Phoenix.LiveViewTest

  alias NeuroScav.ScavengersServer

  # questions are random: skip to the next one until it is of the wanted kind
  defp question(lv, selector) do
    if has_element?(lv, selector) do
      lv
    else
      lv |> element("#quiz-answer-common, #quiz-card-0") |> render_click()
      lv |> element("#btn-quiz-next") |> render_click()
      question(lv, selector)
    end
  end

  defp text(lv, selector),
    do: lv |> element(selector) |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()

  test "a right rarity guess scores, the rule shows and the next question resets", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/quiz")
    lv = question(lv, "#quiz-name")
    score = text(lv, "#quiz-score")

    rarity = lv |> text("#quiz-name") |> String.trim() |> ScavengersServer.check_name()
    html = lv |> element("#quiz-answer-#{rarity.rarity}") |> render_click()

    assert html =~ "Верно!"
    assert has_element?(lv, "#quiz-answer-#{rarity.rarity}.quiz-right")
    assert has_element?(lv, "#quiz-answer-common[disabled]")

    [right, total] =
      Regex.scan(~r/\d+/, score) |> List.flatten() |> Enum.map(&String.to_integer/1)

    assert text(lv, "#quiz-score") =~ "Угадано: #{right + 1} из #{total + 1}"

    lv |> element("#btn-quiz-next") |> render_click()
    refute has_element?(lv, "#btn-quiz-next")
  end

  test "a duel shows both cards' stats after the guess", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/quiz")
    lv = question(lv, "#quiz-card-0")
    refute render(lv) =~ "Сила"

    html = lv |> element("#quiz-card-0") |> render_click()

    assert html =~ "Верно!" or html =~ "Мимо!"
    assert has_element?(lv, "#quiz-card-0 .battle-stats")
    assert has_element?(lv, "#quiz-card-1 .battle-stats")
    assert has_element?(lv, ".quiz-card.quiz-right")
  end
end
