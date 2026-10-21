defmodule NeuroScavWeb.Presence do
  @moduledoc """
  Who has the site open right now, keyed by user id (see `NeuroScavWeb.OnlineCounter`).
  """

  use Phoenix.Presence, otp_app: :neuro_scav, pubsub_server: NeuroScav.PubSub
end
