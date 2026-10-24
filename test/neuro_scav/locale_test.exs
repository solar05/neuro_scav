defmodule NeuroScav.LocaleTest do
  use ExUnit.Case, async: true

  alias NeuroScav.Locale

  test "sets a known locale and returns it, the default one for anything else" do
    assert Locale.setup_locale("en") == "en"
    assert Gettext.get_locale(NeuroScavWeb.Gettext) == "en"

    for stranger <- ["xx", nil, 42] do
      assert Locale.setup_locale(stranger) == "ru"
      assert Gettext.get_locale(NeuroScavWeb.Gettext) == "ru"
    end
  end
end
