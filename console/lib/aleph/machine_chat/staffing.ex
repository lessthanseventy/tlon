defmodule Console.MachineChat.Staffing do
  @moduledoc """
  Pure pick logic for who gets staffed as a new chat thread's lead. Pulled out of `Loop` (which
  grabs the TTY and is deliberately not unit-tested) so the picking RULE — an explicit @-mention
  wins, else the operator's configured default — has its own seam to test.
  """

  alias Console.MachineChat.Triage
  alias Console.Mention

  @doc """
  The coworker to staff on a new thread, in routing order (per-thread-agents Slice E):

    1. the first @-mentioned coworker (resolved against `roster`) — you already decided, no
       classification hop;
    2. else intent triage (`Console.MachineChat.Triage`): explicit review/plan/research intent
       staffs that specialist archetype's roster worker;
    3. else `default` (the operator's persisted override, or the roster's builder-else-worker).
  """
  @spec pick_coworker(String.t(), String.t() | nil, [map()]) :: String.t() | nil
  def pick_coworker(text, default, roster \\ []) do
    case Mention.mentions(text, roster) do
      [{handle, _window} | _] -> handle
      [] -> Triage.lead(text, roster) || default
    end
  end

  @doc """
  Why `pick_coworker/3` chose `handle` for `text` — `:mention` (the operator named them),
  `:triage` (intent classification), or `:default`. Powers the staffing note posted into the
  thread, which is both UX (Slack-style "who's on it") and the observability that makes triage
  misroutes visible instead of guessed at.
  """
  @spec route_reason(String.t(), String.t(), [map()]) :: :mention | :triage | :default
  def route_reason(text, handle, roster) do
    cond do
      match?([{^handle, _} | _], Mention.mentions(text, roster)) -> :mention
      Triage.lead(text, roster) == handle -> :triage
      true -> :default
    end
  end

  @doc """
  The roster-derived default lead for a thread with no explicit @-mention: the roster's
  builder-archetype entry, else its first WORKER entry — never the meta surveyor (Slice B:
  tertius is the vantage, not a leaf lead; a worker-less roster is a misconfiguration the caller
  surfaces as a leaderless thread, not one tertius should absorb). `nil` when no worker resolves.
  Deliberately never invents a stand-in handle: a guessed `-machine` that was never registered as
  a server agent gives `Server.assign_lead/2` nothing to bind, and the thread ends up leaderless
  with nobody listening (the machine-chat silence bug).
  """
  @spec default_coworker([map()]) :: String.t() | nil
  def default_coworker(roster), do: builder_handle(roster) || worker_handle(roster)

  # The roster's builder-archetype handle, or nil (a builder-less cast).
  defp builder_handle(roster) do
    case Enum.find(roster, &(archetype_of(&1) in ["builder", :builder])) do
      nil -> nil
      entry -> handle(entry)
    end
  end

  # The first worker (non-meta) handle — `Profiles.leaf_handles/1` already normalizes archetypes
  # and drops meta/unknown entries.
  defp worker_handle(roster), do: List.first(Console.Profiles.leaf_handles(roster))

  # The server handle convention: profile name + "-machine". Tolerates string (JSON) or atom keys.
  defp handle(entry), do: "#{entry["name"] || entry[:name]}-machine"
  defp archetype_of(entry), do: entry["archetype"] || entry[:archetype]
end
