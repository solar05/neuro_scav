defmodule NeuroScav.DataCase do
  @moduledoc """
  Setup for tests that need the application's data layer.

  Helpers shared by such tests go here. If the test case interacts with the
  database, we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use NeuroScav.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias NeuroScav.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import NeuroScav.DataCase
    end
  end

  setup tags do
    NeuroScav.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(NeuroScav.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
