defmodule Server do
  @moduledoc """
  The boundary of the server system (enforced by the `:boundary` compiler — a violation is a
  compile warning, and the gate runs `--warnings-as-errors`, so reaching into a non-exported
  module fails `mise run check`).

  The exports below ARE server' public surface — what a consumer (console, an MCP adapter) may
  call. Everything else (`Repo`, the schemas' changesets, `Switchboard`, `Agent`, `Session`,
  the event/fact/issue internals) is this module's own business: reach for it from outside and
  the build says no. Widening the surface is a one-line diff HERE, which is the point — the
  surface creeps only on purpose, reviewed in this file's history.
  """

  use Boundary,
    deps: [],
    exports: [
      # The channel: threads, messages, the chorus — the one conversational API.
      Channel,
      # Pub/sub topics for live surfaces (console subscribes; announce stays internal callers').
      Bus,
      # Read models a cockpit renders: who's working, what's known, what's in scope.
      Staff,
      Board,
      Dossier,
      # Compositions: the workspaces context console reads to drive its picker/survey/spawn.
      Workspaces,
      Presence,
      # Explicit thinking/idle presence (console renders it; harnesses declare via MCP).
      Presence.Thinking,
      # The agent-to-agent consult (ask a peer; the answer is mirrored back).
      Consult,
      # Migration pre-flight (console.run refuses to boot a behind db).
      Doctor,
      # The steering-config eval harness (worklines slice 0) — console's scenarios use the
      # same runner/judge, so each module gates its own steering.
      Eval,
      Eval.Scenario,
      Eval.Judge,
      # Identity minting for spawned harnesses (the server-citizen handshake).
      MCP.Spawn,
      # The arbiter behaviour a host implements (console's terminal-writing arbiter).
      Arbiter,
      # The crew behaviour a host implements (console spawns a role's window in-node).
      Crew,
      # Structs read by consumers (pattern-matched, never changeset-built from outside).
      Thread,
      Message
    ]

  @doc "The handle of the agent staffed on a thread (its lead), or nil."
  defdelegate thread_lead(thread_id), to: Server.Channel

  @doc "Staff a thread with an agent by handle — resolves the agent + thread and assigns."
  defdelegate assign_lead(thread_id, handle), to: Server.Channel

  @doc "Staffed machine-scope threads — the `ensure_thread_sessions` candidate list."
  defdelegate staffed_machine_threads, to: Server.Channel

  @doc "The most recent operator-authored message on a thread, or nil — the opening-turn source."
  defdelegate latest_operator_message(thread_id), to: Server.Channel

  @doc "Recall corpus at a glance (facts/embedded/pinned vs budget) — console's Memory pane read."
  defdelegate recall_coverage(), to: Server.Recall, as: :coverage

  @doc "The always-loaded constraint facts (the pinned set) — console's Memory pane shows these."
  defdelegate pinned(), to: Server.Dossier, as: :always_loaded_constraints

  @doc "Habits awaiting the operator's review — the Memory pane's approval queue, newest first."
  defdelegate pending_habits(), to: Server.Dossier

  @doc "Every open workline's live status (stage, gate, blocking check) — the WORKLINES pane read."
  defdelegate workline_statuses(), to: Server.Workline.Ledger, as: :statuses

  @doc """
  Approve a pending habit by id (the Memory pane's `a`) — loads fresh, so a stale row the pane
  rendered can't be acted on. `{:ok, habit}` · `{:error, :not_found}` · `{:error, changeset}`.
  """
  def approve_habit(id), do: with_habit(id, &Server.Dossier.approve_habit/1)

  @doc "Reject a pending habit by id (the Memory pane's `r`) — same load-fresh contract as approve."
  def reject_habit(id), do: with_habit(id, &Server.Dossier.reject_habit/1)

  defp with_habit(id, act) do
    case Server.Dossier.habit(id) do
      nil -> {:error, :not_found}
      habit -> act.(habit)
    end
  end

  @doc """
  Hard-delete a thread by id (the cockpit's `d` on a LEAVES leaf) — loads fresh, so a stale
  row can't be acted on. `{:ok, thread}` · `{:error, :not_found}` · `{:error, :root_machine_thread}`.
  """
  def delete_thread(id) do
    case Server.Channel.thread(id) do
      nil -> {:error, :not_found}
      thread -> Server.Channel.delete_thread(thread)
    end
  end
end
