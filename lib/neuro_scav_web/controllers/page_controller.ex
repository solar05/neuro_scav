defmodule NeuroScavWeb.PageController do
  use NeuroScavWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    redirect(conn, to: ~p(/neuro_scavengers))
  end
end
