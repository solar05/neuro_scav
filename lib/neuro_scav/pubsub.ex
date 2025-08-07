defmodule NeuroScav.Pubsub do
  @moduledoc """
  Main pubsub module.
  """

  alias Phoenix.PubSub

  def subscribe(%{"user_id" => user_id}) do
    PubSub.subscribe(NeuroScav.PubSub, user_topic(user_id))
  end

  def broadcast(info \\ %{}) do
    PubSub.broadcast(
      NeuroScav.PubSub,
      user_topic("2483795d-f57c-4b88-be49-6617fb7a9a34"),
      "lalal"
    )
  end

  def broadcast(user_id, {message, payload}) do
    PubSub.broadcast(NeuroScav.PubSub, user_topic(user_id), {message, payload})
  end

  def user_topic(%{"user_id" => user_id}) do
    "neuro_user:" <> user_id
  end

  def user_topic(user_id) when is_binary(user_id) do
    "neuro_user:" <> user_id
  end
end
