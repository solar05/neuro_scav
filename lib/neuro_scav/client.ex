defmodule NeuroScav.Client do
  @moduledoc """
  Client for neuro interactions.
  """

  require Logger

  def init do
    Ollama.init(base_url: get_base_url(), receive_timeout: 60_000)
  end

  def generate_scav(client, language \\ "en") do
    language = present_language(language)

    Ollama.completion(client,
      model: model(),
      prompt: present_promt(language),
      format: "json",
      options: %{"think" => false, "format" => "json"}
    )
    |> parse_answer()
  end

  # defp parse_answer({:ok, %{"response" => response, "total_duration" => _total_duration}}) do
  # total_duration_seconds = total_duration / 1_000_000_000
  defp parse_answer({:ok, %{"response" => response}}) do
    {:ok, response}
    # case Jason.decode(response) do
    #   {:ok, parsed_response} ->
    #     Logger.info("Taken time for request #{total_duration_seconds}")
    #     {:ok, parsed_response}
    #   {:error, error} ->
    #     Logger.info("Some shit happens when parsing response #{inspect(error)}")
    #     {:error, :incorrect_scavenger}
    # end
  end

  defp get_base_url do
    Application.get_env(:neuro_scav, NeuroScav.NeuroClient)[:api_url]
  end

  defp model, do: "gemma3:4b"

  defp present_promt(_language) do
    "1 + 2"
    # "Generate scavenger name in #{language} language"
  end

  defp present_language("en"), do: "english"
  defp present_language("ru"), do: "russian"
  defp present_language(_), do: raise(ArgumentError, "invalid language")
end
