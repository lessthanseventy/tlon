defmodule Server.Eval.Scenario do
  @moduledoc """
  One eval scenario. `:assert` mode: `run` produces an output, `expect` judges it true/false —
  the deterministic, gate-safe kind. `:judge` mode: `judge_prompt` turns the output into a
  prompt for the LLM judge (`Server.Eval.Judge`), which scores 1–5 per dimension with a
  rationale — the kind that needs a model and runs on demand.
  """

  @enforce_keys [:name, :family, :mode, :run]
  defstruct [:name, :family, :mode, :run, :expect, :judge_prompt]

  @type t :: %__MODULE__{
          name: String.t(),
          family: atom(),
          mode: :assert | :judge,
          run: (-> term()),
          expect: (term() -> boolean()) | nil,
          judge_prompt: (term() -> String.t()) | nil
        }
end
