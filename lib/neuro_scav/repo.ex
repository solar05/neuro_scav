defmodule NeuroScav.Repo do
  use Ecto.Repo,
    otp_app: :neuro_scav,
    adapter: Ecto.Adapters.Postgres
end
