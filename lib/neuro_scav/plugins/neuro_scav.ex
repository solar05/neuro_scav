defmodule PromEx.Plugins.NeuroScav do
  @moduledoc false

  use PromEx.Plugin

  @processed_request_count ~w[prom_ex plugin neuro_scav requests count]a
  @processed_request_measure ~w[prom_ex plugin neuro_scav requests batch processed]a

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = Keyword.get(opts, :metric_prefix, PromEx.metric_prefix(otp_app, :neuro_scav))

    [
      processed_request_measure(metric_prefix)
    ]
  end

  @spec processed_request_count() :: [atom()]
  def processed_request_count(), do: @processed_request_count

  @spec processed_request_measure() :: [atom()]
  def processed_request_measure(), do: @processed_request_measure

  defp processed_request_measure(metric_prefix) do
    Event.build(
      :processed_request_measure,
      [
        counter(
          metric_prefix ++ ~w[requests count total]a,
          event_name: @processed_request_count,
          description: "request to neuro model total"
        ),
        distribution(
          metric_prefix ++ ~w[requests batch processed duration milliseconds]a,
          event_name: @processed_request_measure,
          description: "Time to process requests in milliseconds",
          measurement: :duration,
          reporter_options: [
            buckets: [150, 200, 500, 1_000, 5_000, 10_000, 30_000, 60_000]
          ],
          unit: :millisecond,
          measurement: fn measurements, _metadata ->
            measurements[:duration]
          end
        )
      ]
    )
  end
end
