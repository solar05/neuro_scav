defmodule NeuroScav.FakeClient do
  @moduledoc false

  def generate_scav(_lang) do
    {:ok, %{}}
  end
end

defmodule NeuroScav.IncorrectFakeClient do
  @moduledoc false

  def generate_scav(_lang) do
    {:error, :error}
  end
end
