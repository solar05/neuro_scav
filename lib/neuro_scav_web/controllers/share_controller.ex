defmodule NeuroScavWeb.ShareController do
  use NeuroScavWeb, :controller

  @card_themes ~w(void lava swamp arctic storm rust toxic blood abyss nebula)

  def show(conn, %{"token" => token}) do
    case decode_token(token) do
      {:ok, name, rarity} ->
        theme_index = abs(:erlang.phash2(name)) |> rem(length(@card_themes))
        theme = Enum.at(@card_themes, theme_index)

        conn
        |> put_root_layout(html: {NeuroScavWeb.Layouts, :share})
        |> put_layout(false)
        |> render(:show, name: name, rarity: rarity, theme: theme, token: token)

      :error ->
        conn
        |> put_status(:bad_request)
        |> put_root_layout(html: {NeuroScavWeb.Layouts, :share})
        |> put_layout(false)
        |> render(:show, name: nil, rarity: nil, theme: "void", token: token)
    end
  end

  defp decode_token(token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         [name, rarity] <- String.split(decoded, "|", parts: 2) do
      {:ok, name, rarity}
    else
      _ -> :error
    end
  end
end
