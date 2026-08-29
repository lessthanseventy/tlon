defmodule Server.Eval.Judge.Claude do
  @moduledoc """
  LLM-as-judge over a headless CLI. The command and model are CONFIGURATION, not design
  (funes AGENTS.md): `config :server, eval_judge_cmd: ..., eval_judge_model: ...` — defaults
  to Claude Code's `claude -p` on the cheap alias (the plan bucket judges; fan-out stays off
  the expensive tier per the subagent routing rule). The scenario's prompt states the
  dimensions; this adapter only adds the strict-JSON reply contract and parses it.
  """

  @behaviour Server.Eval.Judge

  @contract """
  You are a strict evaluator. Score the material below on the dimensions it names, each an
  integer 1 (worst) to 5 (best). Respond with ONLY a JSON object, no prose around it:
  {"scores": {"<dimension>": <1-5>, ...}, "rationale": "<one sentence>"}
  """

  @impl true
  def score(prompt) do
    with {:ok, out} <- Server.ModelCli.prompt(@contract <> "\n" <> prompt, :eval_judge_cmd, :eval_judge_model) do
      parse(out)
    end
  end

  # Score keys stay STRINGS: the runner only reads values, and atomizing model-authored
  # keys would mint unbounded atoms. Blob extraction is Server.JsonBlob's (shared).
  @doc false
  def parse(out) do
    case Server.JsonBlob.first_valid(out, &shape/1) do
      nil -> {:error, {:unparseable_judgement, String.slice(out, 0, 200)}}
      judgement -> {:ok, judgement}
    end
  end

  defp shape(%{"scores" => scores, "rationale" => rationale}) when map_size(scores) > 0,
    do: %{scores: scores, rationale: rationale}

  defp shape(_decoded), do: nil
end
