defmodule TurnstileMock do
  @moduledoc """
  Mocks for turnstile.
  """

  def refresh(socket), do: socket

  def verify(_) do
    if :persistent_term.get({TurnstileMock, :error}, false) do
      {:error, :invalid_token}
    else
      {:ok, %{}}
    end
  end

  def set_error(value), do: :persistent_term.put({TurnstileMock, :error}, value)
end
