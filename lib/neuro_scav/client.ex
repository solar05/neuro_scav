defmodule NeuroScav.Client do
  @moduledoc """
  Ollama AI client for scavenger generation.

  This module handles communication with Ollama, a local LLM service,
  to generate AI-powered scavenger names with randomly selected first and last names.

  ## Configuration

  Requires Ollama to be running and accessible at the configured API URL:
  - Environment variable: `NEURO_MODEL_API_URL`
  - Default: `http://localhost:11434/api`
  - Configured via: `config/runtime.exs`

  ## Model

  Uses the `scav:latest` Ollama model for generation.

  ## Supported Languages

  - `"en"` - English
  - `"ru"` - Russian

  ## Example

      iex> NeuroScav.Client.generate_scav("en")
      {:ok, "John Smith"}

      iex> NeuroScav.Client.generate_scav("ru")
      {:ok, "Иван Петров"}
  """

  @default_temperature 0.8
  @default_model "scav:latest"
  @ai_timeout 60_000

  require Logger

  @doc """
  Initialize Ollama client with configured API URL.

  Returns an initialized Ollama client ready for completions.

  ## Returns

  Ollama client struct configured with:
  - Base URL from environment configuration
  - 60-second receive timeout
  """
  @spec init() :: term()
  def init do
    Ollama.init(base_url: get_base_url(), receive_timeout: @ai_timeout)
  end

  @doc """
  Generate an AI-powered scavenger name.

  Calls Ollama AI service to generate a random first and last name pair
  in the specified language. The generated name is returned as a string
  in the format "FirstName LastName".

  ## Parameters

  - `language` - Language code ("en" or "ru"), defaults to "en"

  ## Returns

  - `{:ok, name}` - Scavenger name as string (e.g., "John Smith")
  - `{:error, reason}` - Error atom or error message

  ## Errors

  - `:incorrect_scavenger` - Failed to parse AI response as valid JSON
  - Error message from Ollama if connection/request fails
  """
  @spec generate_scav(String.t()) :: {:ok, String.t()} | {:error, atom() | String.t()}
  def generate_scav(language \\ "en") do
    client = init()
    language = present_language(language)

    Ollama.completion(client,
      model: @default_model,
      prompt: present_prompt(language),
      format: "json",
      keep_alive: -1,
      options: %{"think" => false, "format" => "json", "temperature" => @default_temperature}
    )
    |> parse_answer()
  end

  @doc false
  @spec parse_answer({:ok, map()} | {:error, map()}) ::
          {:ok, String.t()} | {:error, atom() | String.t()}
  defp parse_answer({:ok, %{"response" => response, "total_duration" => total_duration}}) do
    total_duration_seconds = total_duration / 1_000_000_000

    case Jason.decode(response) do
      {:ok, %{"firstName" => first_name, "lastName" => last_name}} ->
        Logger.info("AI request completed in #{total_duration_seconds}s")
        {:ok, "#{first_name} #{last_name}"}

      {:error, error} ->
        Logger.warning("Failed to parse AI response: #{inspect(error)}")
        {:error, :incorrect_scavenger}
    end
  end

  defp parse_answer({:error, %{status: _status, message: message}}) do
    {:error, message}
  end

  defp parse_answer({:error, %{reason: reason}}) do
    {:error, reason}
  end

  @doc false
  @spec get_base_url() :: String.t()
  defp get_base_url do
    Application.get_env(:neuro_scav, NeuroScav.NeuroClient)[:api_url]
  end

  @doc false
  @spec present_prompt(String.t()) :: String.t()
  defp present_prompt(language) do
    "gen#{language}"
  end

  @doc false
  @spec present_language(String.t()) :: String.t()
  defp present_language("en"), do: "en"
  defp present_language("ru"), do: "ru"
  defp present_language(_), do: raise(ArgumentError, "invalid language")
end
