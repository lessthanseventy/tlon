defmodule Console.MachineChat.Triage do
  @moduledoc """
  Intent triage for UNROUTED threads (per-thread-agents Slice E): when the operator opens a
  thread without @-naming a coworker, classify the opening text to a specialist archetype and
  staff that roster worker as the lead — the "tertius triages" role, done here as deterministic
  keyword rules (the design's open question resolved: rules first, a model call only if they
  prove too dumb).

  Deliberately CONSERVATIVE: only explicit intent verbs classify (review → reviewer, plan/tickets
  → planner, research/questions → researcher). Anything else returns nil and the caller falls
  through to the worker default (the builder) — so a fuzzy match can never hijack a build task,
  and the operator's @-mention fast path never pays a classification at all (`Staffing` checks
  mentions first).
  """

  # Ordered: the first matching rule wins. Reviewer before researcher so "review this — why does
  # it leak?" stays a review; planner before researcher for the same reason.
  @rules [
    {:reviewer, ~r/\b(review|audit|critique|look\s+over)\b/i},
    {:planner, ~r/\b(plan|roadmap|tickets?|milestones?|break\s+(this|it)\s+down|write\s+a\s+spec)\b/i},
    {:researcher, ~r/\b(research|investigate|look\s+into|find\s+out|dig\s+into|compare)\b/i},
    # Interrogative-shaped: a leading question word AND a trailing "?" — "can you fix X?" stays a
    # build ask (no leading interrogative we claim), "why does the cache miss?" is research.
    {:researcher, ~r/\A\s*(why|what|how|where|when|which|who)\b.*\?\s*\z/is}
  ]

  @doc "The specialist archetype the text's intent names, or nil (no explicit intent — default lead)."
  @spec archetype(String.t() | nil) :: atom() | nil
  def archetype(nil), do: nil

  def archetype(text) do
    Enum.find_value(@rules, fn {arch, re} -> if Regex.match?(re, text), do: arch end)
  end

  @doc """
  The roster WORKER handle triage staffs for `text`, or nil (no intent matched, or the workspace's
  roster has no worker of that archetype — the caller's default decides). Meta entries never
  resolve (tertius does the triaging; it does not take the leaf).
  """
  @spec lead(String.t() | nil, [map()]) :: String.t() | nil
  def lead(text, roster) do
    with arch when not is_nil(arch) <- archetype(text) do
      roster
      |> Enum.map(&Console.Profiles.roster_entry/1)
      |> Enum.find_value(fn %{archetype: a, name: n} -> if a == arch, do: "#{n}-machine" end)
    end
  end
end
