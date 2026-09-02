defmodule Server.Recall.Certainty do
  @moduledoc """
  Time-aware certainty (design: `docs/plans/2026-08-19-funes-forgetting-design.md`), the
  verification half-life. `stated > checked > opinion` like `Server.MCP.Brief.certainty/1`, but
  a `:checked` label is EARNED and PERISHABLE: it requires a check that actually *passed*, and
  it decays back to `:opinion` once that pass is older than the half-life. "We verified X" stops
  being trusted unless someone re-runs it. Pure.
  """

  # A verification stays authoritative ~a month before it must be re-earned.
  @default_half_life_s 30 * 24 * 3600

  @type label :: :stated | :checked | :opinion

  @doc """
  The certainty label for a fact as of `now`. `fact` carries `:provenance` and `:last_pass_at`
  (the newest `check_passed` time, or nil). `half_life_s` overrides the staleness window.
  """
  @spec of(map(), DateTime.t(), keyword()) :: label()
  def of(fact, now, opts \\ [])

  def of(%{provenance: "stated"}, _now, _opts), do: :stated

  def of(%{provenance: "derived", last_pass_at: %DateTime{} = at}, now, opts) do
    hl = Keyword.get(opts, :half_life_s, @default_half_life_s)
    if DateTime.diff(now, at, :second) <= hl, do: :checked, else: :opinion
  end

  def of(_fact, _now, _opts), do: :opinion
end
