defmodule Server.Memory.Extractor do
  @moduledoc """
  The turn-pass extraction seam: completed-turn messages + the thread's existing facts →
  0..3 durable fact candidates. A behaviour so the pass tests with a stub and the adapter
  (model, CLI) stays configuration.
  """

  @callback extract(messages :: [Server.Message.t()], existing_facts :: [Server.Fact.t()]) ::
              {:ok, [%{required(:kind) => String.t(), required(:text) => String.t(), optional(:intent) => String.t()}]}
              | {:error, term()}
end

defmodule Server.Memory.Extractor.Claude do
  @moduledoc """
  Extraction over a headless CLI — command and model are configuration, not design
  (`config :server, memory_extractor_cmd: ..., memory_extractor_model: ...`; defaults
  `claude`/`haiku` — the cheap tier, per the routing rule).
  """

  @behaviour Server.Memory.Extractor

  @contract """
  You extract DURABLE knowledge from an agent conversation turn. From the messages below,
  return at most 3 facts worth remembering across sessions: decisions made, constraints
  stated, lessons learned. Skip chatter, status, and anything the EXISTING FACTS already
  cover. Respond with ONLY a JSON object:
  {"facts": [{"kind": "decision"|"constraint"|"learned", "text": "<one claim>", "intent": "<what it's for>"}]}
  An empty list is the right answer for an uneventful turn.
  """

  @impl true
  def extract(messages, existing_facts) do
    prompt =
      @contract <>
        "\nEXISTING FACTS:\n" <>
        Enum.map_join(existing_facts, "\n", & &1.text) <>
        "\n\nMESSAGES:\n" <>
        Enum.map_join(messages, "\n", &"#{&1.author}: #{&1.body}")

    with {:ok, out} <- Server.ModelCli.prompt(prompt, :memory_extractor_cmd, :memory_extractor_model) do
      parse(out)
    end
  end

  @doc false
  def parse(out) do
    case Server.JsonBlob.first_valid(out, &shape/1) do
      nil -> {:error, {:unparseable_extraction, String.slice(out, 0, 200)}}
      facts -> {:ok, facts}
    end
  end

  defp shape(%{"facts" => facts}) when is_list(facts) do
    facts
    |> Enum.filter(&match?(%{"kind" => k, "text" => t} when is_binary(t) and k in ~w(decision constraint learned), &1))
    |> Enum.map(&%{kind: &1["kind"], text: &1["text"], intent: &1["intent"]})
  end

  defp shape(_decoded), do: nil
end
