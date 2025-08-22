defmodule TurnstileMock do
  @moduledoc """
  Mocks for turnstile.
  """

  def refresh(socket), do: socket
  def verify(_, _), do: {:ok, %{}}
end
