defmodule NeuroScavWeb.NavMenuTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias NeuroScavWeb.CoreComponents

  defp summary(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("summary")
    |> LazyHTML.text()
    |> String.replace("▾", "")
    |> String.trim()
  end

  test "shows Single by default and hides every page in the dropdown" do
    html = render_component(&CoreComponents.nav_menu/1, action: :neuro_scavengers)

    assert summary(html) == "Дичок"

    for path <-
          ~w(/ /team_scavengers /statistics /wheel /check_name /collection /battle /quiz /raid),
        do: assert(html =~ ~s(href="#{path}"))

    refute html =~ "/neuro_scavengers"
  end

  test "shows the current page in the navbar" do
    html = render_component(&CoreComponents.nav_menu/1, action: :wheel)

    assert summary(html) == "Колесо"
    assert html =~ ~s(class="nav-link blended-old-nav")
  end
end
