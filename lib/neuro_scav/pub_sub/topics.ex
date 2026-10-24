defmodule NeuroScav.PubSub.Topics do
  @moduledoc """
  PubSub topic constants and topic generation utilities.

  This module centralizes all PubSub topic definitions used throughout
  the application, making it easier to maintain topic naming conventions
  and enabling AI systems to understand the event structure.

  ## Topic Patterns

  The application uses hierarchical topic patterns:
  - `statistics:lobby` - Global statistics updates
  - `user:<user_id>` - User-specific events
  - `team:<team_id>` - Team-specific events
  - `<event_type>:<entity_id>` - Event-based routing

  ## Usage

  Instead of using hardcoded strings:

      # ❌ Avoid hardcoding
      PubSub.broadcast(NeuroScav.PubSub, "user:123", {:scavenger_generated, scav})

      # ✅ Prefer using constants
      PubSub.broadcast(NeuroScav.PubSub, Topics.user_topic("123"), {:scavenger_generated, scav})
  """

  # Statistics topics
  @doc """
  Global statistics topic for broadcasting aggregated statistics updates.

  Used by StatsCounterServer to publish updated counter values, and by
  `Scavengers.record_raid/1` to publish the raid statistics.
  All subscribers receive the latest statistics.
  """
  @spec statistics_topic() :: String.t()
  def statistics_topic, do: "statistics:lobby"

  @doc """
  Global topic for legendary finds, shown to everyone else as a toast.
  """
  @spec finds_topic() :: String.t()
  def finds_topic, do: "finds:lobby"

  @doc """
  Topic of one card battle room; carries `{:battle_updated, state}` and `:battle_closed`.
  """
  @spec battle_topic(String.t()) :: String.t()
  def battle_topic(id), do: "battle:#{id}"

  # User-specific topics
  @doc """
  User-specific topic for events related to a particular user.

  Topics:
  - `:single_generated` - Single scavenger was generated
  - `:team_generated` - Team of scavengers was generated
  - `:request_completed` - User request completed
  """
  @spec user_topic(String.t(), atom() | String.t()) :: String.t()
  def user_topic(user_id, page) when is_binary(user_id), do: "user:#{user_id}:#{page}"
end
