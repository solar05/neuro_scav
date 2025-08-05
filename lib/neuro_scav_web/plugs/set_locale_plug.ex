defmodule NeuroScavWeb.Plugs.SetLocale do
  @moduledoc """
  Localization changer plug.
  """

  import Plug.Conn
  @supported_locales Gettext.known_locales(NeuroScavWeb.Gettext)

  def init(_options), do: nil

  def call(conn, _options) do
    case fetch_locale_from(conn) do
      nil ->
        conn

      locale ->
        NeuroScavWeb.Gettext |> Gettext.put_locale(locale)
        put_resp_cookie(conn, "lang", locale, max_age: 365 * 24 * 60 * 60)
    end
  end

  defp fetch_locale_from(conn) do
    (conn.params["lang"] || conn.cookies["lang"])
    |> check_locale
  end

  defp check_locale(locale) when locale in @supported_locales, do: locale
  defp check_locale(_), do: nil
end
