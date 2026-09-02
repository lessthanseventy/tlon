defmodule Server.Recall.Strength do
  @moduledoc """
  A fact's memory STRENGTH: the decayed sum of signed touches (design:
  `docs/plans/2026-08-19-funes-forgetting-design.md`). A touch is something funes records —
  birth, a passing/failing recheck, a citation-and-use, a supersede. Recent and repeatedly
  confirmed facts stay strong; a failed recheck or a supersede pulls hard the other way. This
  is the forgetting curve: the recall layer multiplies strength by relevance to rank the
  working set, and low-strength facts fall out of context (never off disk). Pure.
  """

  # Touch weights — few, deliberately UN-calibrated (design §strength: tune from real use, never
  # by feel). Empirical confirmation (a real recheck passing) outweighs mere birth; a failed
  # recheck or a supersede is a hard negative.
  @weights %{
    "created" => 1.0,
    "cited" => 0.5,
    "check_passed" => 2.0,
    "check_failed" => -2.0,
    "superseded" => -3.0
  }

  # Freshness half-life: a touch's contribution halves every ~two weeks untouched.
  @default_half_life_s 14 * 24 * 3600

  @type touch :: %{weight: number(), at: DateTime.t()}

  @doc "The weight for a named touch kind (0.0 for an unknown kind)."
  @spec weight(String.t()) :: float()
  def weight(kind), do: Map.get(@weights, kind, 0.0)

  @doc "Decayed sum of signed touches as of `now`. `half_life_s` overrides the decay window."
  @spec of([touch()], DateTime.t(), keyword()) :: float()
  def of(touches, now, opts \\ []) do
    hl = Keyword.get(opts, :half_life_s, @default_half_life_s)
    Enum.reduce(touches, 0.0, fn %{weight: w, at: at}, acc -> acc + w * decay(now, at, hl) end)
  end

  @doc """
  Map a fact's recorded history into signed touches: its birth, its correlated touch events
  (`check_passed`/`check_failed`/`cited`), and a hard-negative if superseded. Each event kind maps
  through `weight/1`, so a new touch kind costs only a weight entry.
  """
  @spec touches_for(map(), DateTime.t()) :: [touch()]
  def touches_for(%{created_at: created_at} = fact, now) do
    events = Map.get(fact, :touches, [])
    superseded? = Map.get(fact, :superseded?, false)

    [%{weight: weight("created"), at: created_at}] ++
      Enum.map(events, fn %{kind: kind, at: at} -> %{weight: weight(kind), at: at} end) ++
      if(superseded?, do: [%{weight: weight("superseded"), at: now}], else: [])
  end

  # Half-life decay: a touch's weight halves every `hl` seconds since it happened. A future-dated
  # touch (clock skew) clamps to no decay rather than amplifying.
  defp decay(now, at, hl) do
    dt = max(DateTime.diff(now, at, :second), 0)
    :math.pow(0.5, dt / hl)
  end
end
