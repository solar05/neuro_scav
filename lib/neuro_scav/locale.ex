defmodule NeuroScav.Locale do
  @moduledoc """
  Locale utilization functions.
  """

  alias NeuroScavWeb.Plugs.SetLocale

  @doc """
  Sets the language the current process's texts are told in and returns it:
  `locale` if the site has it, the default one for anything else (nil, a
  stranger's `lang`).
  """
  @spec setup_locale(term()) :: String.t()
  def setup_locale(locale) do
    locale = SetLocale.known_locale(locale)
    SetLocale.put_gettext_locale(locale)
    locale
  end

  def get_text(msg) do
    Gettext.gettext(NeuroScavWeb.Gettext, msg)
  end

  def get_text(msg, params) do
    Gettext.gettext(NeuroScavWeb.Gettext, msg, params)
  end
end
