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

defmodule NeuroScav.SlowFakeClient do
  @moduledoc false

  # tells the test it's at work, answers once the test says so
  def generate_scav(_lang) do
    send(:slow_fake_client_test, {:generating, self()})

    receive do
      :answer -> {:ok, %{"name" => "Neuro Scav"}}
    end
  end
end

defmodule NeuroScav.RaisingFakeClient do
  @moduledoc false

  def generate_scav(_lang), do: raise("the model is down")
end
