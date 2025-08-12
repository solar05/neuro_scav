defmodule NeuroScav.Locale do
  @moduledoc """
  Locale utilization functions.
  """

  alias NeuroScavWeb.Plugs.SetLocale

  def setup_locale(locale) do
    SetLocale.put_gettext_locale(locale)
  end

  def get_text(msg) do
    Gettext.gettext(NeuroScavWeb.Gettext, msg)
  end

  def get_text(msg, params) do
    Gettext.gettext(NeuroScavWeb.Gettext, msg, params)
  end
end
