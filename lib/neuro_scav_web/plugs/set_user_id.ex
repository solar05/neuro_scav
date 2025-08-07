defmodule NeuroScavWeb.Plugs.SetUserId do
  @moduledoc """
  User id setter plug.
  """

  import Plug.Conn

  def init(_options), do: nil

  def call(conn, _options) do
    case fetch_user_id_from(conn) do
      nil ->
        put_user_id(conn)

      _user_id ->
        conn
    end
  end

  defp put_user_id(conn) do
    put_session(conn, "user_id", generate_user_id())
  end

  defp generate_user_id() do
    Uniq.UUID.uuid4()
  end

  defp fetch_user_id_from(conn) do
    get_session(conn)
    |> check_user_id()
  end

  defp check_user_id(%{"user_id" => user_id}) when is_binary(user_id), do: user_id
  defp check_user_id(_), do: nil
end
