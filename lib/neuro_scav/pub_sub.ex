defmodule NeuroScav.PubSub do
  @moduledoc """
  PubSub broadcasting module for real-time events.

  This module provides high-level PubSub abstractions for:
  - User-specific event broadcasting
  - Global statistics updates
  - Topic subscription management

  Uses Phoenix.PubSub for underlying pub/sub functionality.

  ## Examples

  Subscribe to user events:
      NeuroScav.PubSub.subscribe("user", %{"user_id" => user_id})

  Subscribe to statistics:
      NeuroScav.PubSub.subscribe_statistics()

  Broadcast user event:
      NeuroScav.PubSub.broadcast(user_id, {:scavenger_generated, :single_scavenger, scavenger})

  Broadcast statistics update:
      NeuroScav.PubSub.broadcast_statistics(updated_stats)
  """

  alias Phoenix.PubSub
  alias NeuroScav.PubSub.Topics

  @doc """
  Subscribe to user-specific events.

  Parameters:
    - topic: Event category (string)
    - user_data: Map containing :user_id key

  ## Example
      subscribe("user", %{"user_id" => "user123"})
  """
  @spec subscribe(String.t(), map()) :: :ok | {:error, term()}
  def subscribe(topic, %{"user_id" => user_id}) do
    PubSub.subscribe(NeuroScav.PubSub, Topics.user_topic(user_id, topic))
  end

  @doc """
  Subscribe to global statistics updates.

  All statistics counter changes are broadcast to this topic.
  """
  @spec subscribe_statistics() :: :ok | {:error, term()}
  def subscribe_statistics() do
    PubSub.subscribe(NeuroScav.PubSub, Topics.statistics_topic())
  end

  @doc """
  Broadcast an event with payload to a user.

  Parameters:
    - user_id: Target user ID
    - {message, topic, payload}: 3-tuple with message type, topic, and data

  Or broadcast an event without payload to a user:
    - {message, topic}: 2-tuple with message type and topic

  ## Examples

      broadcast(user_id, {:scavenger_generated, :single_scavenger, scavenger_map})
      broadcast(user_id, {:request_completed, :single_scavenger})
  """
  @spec broadcast(String.t(), {atom(), String.t(), term()}) :: :ok | {:error, term()}
  def broadcast(user_id, {message, topic, payload}) do
    PubSub.broadcast(NeuroScav.PubSub, Topics.user_topic(user_id, topic), {message, payload})
  end

  @spec broadcast(String.t(), {atom(), String.t()}) :: :ok | {:error, term()}
  def broadcast(user_id, {message, topic}) do
    PubSub.broadcast(NeuroScav.PubSub, Topics.user_topic(user_id, topic), message)
  end

  @doc """
  Broadcast updated statistics to all subscribers.

  Notifies all connected clients of new statistics values.
  Called by StatsCounterServer after counter updates.

  Parameters:
    - new_statistics: Map of counter updates, e.g., %{common: 5, rare: 2}
  """
  @spec broadcast_statistics(map()) :: :ok | {:error, term()}
  def broadcast_statistics(new_statistics) do
    PubSub.broadcast(
      NeuroScav.PubSub,
      Topics.statistics_topic(),
      {:statistics_updated, new_statistics}
    )
  end

  @doc """
  Get the global statistics topic name.

  Returns: "statistics:lobby"
  """
  @spec statistics_topic() :: String.t()
  def statistics_topic do
    Topics.statistics_topic()
  end
end
