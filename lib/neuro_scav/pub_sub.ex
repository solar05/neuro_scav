defmodule NeuroScav.PubSub do
  @moduledoc """
  Main pubsub module.
  """

  alias Phoenix.PubSub

  def subscribe(%{"user_id" => user_id}) do
    PubSub.subscribe(NeuroScav.PubSub, user_topic(user_id))
  end

  def broadcast(user_id, {message, payload}) do
    PubSub.broadcast(NeuroScav.PubSub, user_topic(user_id), {message, payload})
  end

  def broadcast(user_id, message) do
    PubSub.broadcast(NeuroScav.PubSub, user_topic(user_id), message)
  end

  def user_topic(%{"user_id" => user_id}) do
    "neuro_user:" <> user_id
  end

  def user_topic(user_id) when is_binary(user_id) do
    "neuro_user:" <> user_id
  end
end
