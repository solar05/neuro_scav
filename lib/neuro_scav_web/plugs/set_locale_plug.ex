defmodule NeuroScavWeb.Plugs.SetLocale do
  @moduledoc """
  Localization changer plug.
  """

  import Plug.Conn
  @supported_locales Gettext.known_locales(NeuroScavWeb.Gettext)
  @default_locale "en"

  def init(_options), do: nil

  def call(conn, _options) do
    case fetch_locale_from(conn) do
      nil ->
        put_locale(conn, @default_locale)

      locale ->
        NeuroScavWeb.Gettext |> Gettext.put_locale(locale)
        put_locale(conn, locale)
    end
  end

  defp put_locale(conn, locale) do
    conn
    |> put_resp_cookie("lang", locale, max_age: 365 * 24 * 60 * 60)
    |> put_session("lang", locale)
  end

  defp fetch_locale_from(conn) do
    (conn.params["lang"] || conn.cookies["lang"])
    |> check_locale()
  end

  defp check_locale(locale) when locale in @supported_locales, do: locale
  defp check_locale(_), do: nil
end
