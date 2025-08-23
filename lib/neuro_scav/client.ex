defmodule NeuroScav.Client do
  @moduledoc """
  Client for neuro interactions.
  """

  require Logger

  def init do
    Ollama.init(base_url: get_base_url(), receive_timeout: 15_000)
  end

  def generate_scav(language \\ "en") do
    client = init()
    language = present_language(language)

    Ollama.completion(client,
      model: model(),
      prompt: present_promt(language),
      format: "json",
      options: %{"think" => false, "format" => "json"}
    )
    |> parse_answer()
  end

  defp parse_answer({:ok, %{"response" => response, "total_duration" => total_duration}}) do
    total_duration_seconds = total_duration / 1_000_000_000

    case Jason.decode(response) do
      {:ok, %{"firstName" => first_name, "lastName" => last_name}} ->
        Logger.info("Taken time for request #{total_duration_seconds}")
        {:ok, "#{first_name} #{last_name}"}

      {:error, error} ->
        Logger.info("Some shit happens when parsing response #{inspect(error)}")
        {:error, :incorrect_scavenger}
    end
  end

  defp parse_answer({:error, %{status: _status, message: message}}) do
    {:error, message}
  end

  defp parse_answer({:error, %{reason: reason}}) do
    {:error, reason}
  end

  defp get_base_url do
    Application.get_env(:neuro_scav, NeuroScav.NeuroClient)[:api_url]
  end

  defp model, do: "scav:latest"

  defp present_promt(language) do
    "gen#{language}"
  end

  defp present_language("en"), do: "en"
  defp present_language("ru"), do: "ru"
  defp present_language(_), do: raise(ArgumentError, "invalid language")
end
