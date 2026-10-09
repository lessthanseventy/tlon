defmodule Server.Memory.Extractor do
  @moduledoc """
  The turn-pass extraction seam: completed-turn messages + the existing facts it may relate to (the
  thread's own and the nearest in its scope) → 0..3 durable fact candidates, each labelled with
  its relation to an existing fact: `verdict` `"new"`, or `"restates"` / `"corrects"` the fact `old`
  (an existing fact's id), with a one-line `reason`. A behaviour so the pass tests with a stub and
  the adapter (model, CLI) stays configuration.
  """

  @type candidate :: %{
          required(:kind) => String.t(),
          required(:text) => String.t(),
          optional(:intent) => String.t(),
          optional(:verdict) => String.t(),
          optional(:old) => pos_integer() | nil,
          optional(:reason) => String.t() | nil
        }

  @callback extract(messages :: [Server.Message.t()], existing_facts :: [Server.Fact.t()]) ::
              {:ok, [candidate()]} | {:error, term()}
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
  cover. For each fact you return, say how it relates to the EXISTING FACTS:
  - "verdict": "corrects", "old": <its #number> — it and that existing fact cannot both be true
    now (the behaviour was changed, the decision reversed, the value changed);
  - "verdict": "restates", "old": <its #number> — it says EVERYTHING that fact says, in better
    words; if that fact has any detail yours lacks, it is "new";
  - "verdict": "new" — anything else, including detail that leaves the existing fact true.
  When unsure, "new". Respond with ONLY a JSON object:
  {"facts": [{"kind": "decision"|"constraint"|"learned", "text": "<one claim>", "intent": "<what it's for>",
    "verdict": "new"|"restates"|"corrects", "old": <number or null>, "reason": "<one line: why that verdict>"}]}
  An empty list is the right answer for an uneventful turn.
  """

  @impl true
  def extract(messages, existing_facts) do
    prompt =
      @contract <>
        "\nEXISTING FACTS:\n" <>
        Enum.map_join(existing_facts, "\n", &"##{&1.id}: #{&1.text}") <>
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
    |> Enum.map(fn f ->
      verdict = if f["verdict"] in ~w(restates corrects) and is_integer(f["old"]), do: f["verdict"], else: "new"
      old = if verdict != "new", do: f["old"]
      %{kind: f["kind"], text: f["text"], intent: f["intent"], verdict: verdict, old: old, reason: f["reason"]}
    end)
  end

  defp shape(_decoded), do: nil
end
