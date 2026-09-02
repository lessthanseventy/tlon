defmodule Server.Eval.Judge do
  @moduledoc """
  The judge seam: score an eval prompt 1–5 per dimension with a rationale. A behaviour so
  the runner tests with a stub and the adapter (model, CLI, transport) swaps freely.
  """

  @callback score(prompt :: String.t()) ::
              {:ok, %{scores: %{optional(atom() | String.t()) => number()}, rationale: String.t()}}
              | {:error, term()}
end
