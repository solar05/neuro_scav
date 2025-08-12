defmodule NeuroScav.PubSub do
  @moduledoc """
  Main pubsub module.
  """

  alias Phoenix.PubSub

  def subscribe(topic, %{"user_id" => user_id}) do
    PubSub.subscribe(NeuroScav.PubSub, user_topic(topic, user_id))
  end

  def subscribe_statistics() do
    PubSub.subscribe(NeuroScav.PubSub, statistics_topic())
  end

  def broadcast(user_id, {message, topic, payload}) do
    PubSub.broadcast(NeuroScav.PubSub, user_topic(topic, user_id), {message, payload})
  end

  def broadcast(user_id, {message, topic}) do
    PubSub.broadcast(NeuroScav.PubSub, user_topic(topic, user_id), message)
  end

  def broadcast_statistics(new_statistics) do
    PubSub.broadcast(NeuroScav.PubSub, statistics_topic(), {:statistics_updated, new_statistics})
  end

  def statistics_topic do
    "statistics:lobby"
  end

  def user_topic(topic, user_id) when is_binary(user_id) do
    "#{topic}:" <> user_id
  end
end
