defmodule NeuroScavWeb.Plugs.SetLocale do
  @moduledoc """
  Localization changer plug.
  """

  import Plug.Conn
  @supported_locales Gettext.known_locales(NeuroScavWeb.Gettext)
  @default_locale "ru"

  def init, do: init(nil)
  def init(_options), do: nil

  def call(conn, _options), do: put_locale(conn, known_locale(fetch_locale_from(conn)))

  @doc "`locale` if the site has it, the default one (#{@default_locale}) for anything else."
  @spec known_locale(term()) :: String.t()
  def known_locale(locale), do: check_locale(locale) || @default_locale

  def put_gettext_locale(locale) do
    NeuroScavWeb.Gettext |> Gettext.put_locale(locale)
  end

  defp put_locale(conn, locale) do
    put_gettext_locale(locale)

    conn
    |> put_resp_cookie("lang", locale, max_age: 365 * 24 * 60 * 60)
    |> put_session("lang", locale)
  end

  defp fetch_locale_from(conn) do
    (conn.params["lang"] || conn.cookies["lang"]) |> check_locale()
  end

  defp check_locale(locale) when locale in @supported_locales, do: locale
  defp check_locale(_), do: nil
end
