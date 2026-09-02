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
      # The container tier (2026-08-30): projects, the lightweight ticket tracker, notes —
      # peer contexts to Workspaces the console reads/writes for the god line + CRUD screens.
      Projects,
      Tickets,
      Notes,
      Presence,
      # Explicit thinking/idle presence (console renders it; harnesses declare via MCP).
      Presence.Thinking,
      # The agent-to-agent consult (ask a peer; the answer is mirrored back).
      Consult,
      # Migration pre-flight (console.run refuses to boot a behind db).
      Doctor,
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

  alias Server.Workline.Ledger

  @doc "The handle of the agent staffed on a thread (its lead), or nil."
  defdelegate thread_lead(thread_id), to: Server.Channel

  @doc "Staff a thread with an agent by handle — resolves the agent + thread and assigns."
  defdelegate assign_lead(thread_id, handle), to: Server.Channel

  @doc "Staffed machine-scope threads — the `ensure_thread_sessions` candidate list."
  defdelegate staffed_machine_threads, to: Server.Channel
  defdelegate workspace_thread_ids(workspace_id), to: Server.Channel

  @doc "The most recent operator-authored message on a thread, or nil — the opening-turn source."
  defdelegate latest_operator_message(thread_id), to: Server.Channel

  @doc """
  The primary repo dir a thread's work lives in (thread→project→first repo) — the base a per-thread
  worktree or a STACK-zoom lazygit opens against (Slice 4). Takes a thread id or struct.
  `{:ok, path}`, `{:error, :no_repo}`, or `{:error, :no_thread}`.
  """
  def repo_for_thread(%Server.Thread{} = thread), do: Server.Projects.repo_for_thread(thread)

  @doc "A workspace's primary repo dir — the cockpit STACK panel's per-workspace git root. See `Projects.repo_for_workspace/1`."
  defdelegate repo_for_workspace(workspace_id), to: Server.Projects

  def repo_for_thread(thread_id) when is_integer(thread_id) do
    case Server.Channel.thread(thread_id) do
      nil -> {:error, :no_thread}
      thread -> Server.Projects.repo_for_thread(thread)
    end
  end

  @doc """
  Resolve a thread to the working dir a STACK-zoom lazygit (or crew) should open against (Slice 4):
  its project's repo, then — for a workline thread (one with a `slug`) — a lazily-ensured per-thread
  `git worktree` at `.worktrees/<slug>`. A thread with no slug falls back to the repo itself (lazygit
  at the project repo, per the plan). `{:ok, path}`, `{:error, :no_repo | :no_thread | reason}`.
  """
  def worktree_for_thread(%Server.Thread{slug: slug} = thread) do
    case repo_for_thread(thread) do
      {:ok, repo} when is_nil(slug) -> {:ok, repo}
      {:ok, repo} -> Server.Worktree.ensure(repo, slug)
      {:error, _} = error -> error
    end
  end

  def worktree_for_thread(thread_id) when is_integer(thread_id) do
    case Server.Channel.thread(thread_id) do
      nil -> {:error, :no_thread}
      thread -> worktree_for_thread(thread)
    end
  end

  @doc """
  Open a workline from a title at `stage` (any-stage entry) — the tertius `open`/`spike`/`build`
  verbs' door (Slice 4D). `attrs` must carry `:title` + `:stage`; `:workspace_id`/`:project_id`/
  `:parent_thread_id` are optional. `{:ok, thread}` | `{:error, {:invalid_stage, s}}` | `{:error, cs}`.
  """
  def open_workline(%{title: title, stage: stage} = attrs),
    do: Server.Workline.open_titled(title, stage, Map.drop(attrs, [:title, :stage]))

  @doc """
  Approve a parked workline gate by thread id — the tertius `approve N` verb (Slice 4D). `{:ok,
  thread}` (flipped), `{:error, {:artifact_missing, why}}`, `{:error, :nothing_awaiting}`, or
  `{:error, :no_thread}`.
  """
  def approve_workline(thread_id) when is_integer(thread_id) do
    case Server.Channel.thread(thread_id) do
      nil -> {:error, :no_thread}
      thread -> Server.Workline.approve(thread)
    end
  end

  @doc "Recall corpus at a glance (facts/embedded/pinned vs budget) — console's Memory pane read."
  defdelegate recall_coverage(), to: Server.Recall, as: :coverage
  defdelegate recall_coverage(workspace_id), to: Server.Recall, as: :coverage

  @doc "The always-loaded constraint facts (the pinned set) — console's Memory pane shows these."
  defdelegate pinned(), to: Server.Dossier, as: :always_loaded_constraints
  defdelegate pinned(workspace_id), to: Server.Dossier, as: :always_loaded_constraints

  @doc "Habits awaiting the operator's review — the Memory pane's approval queue, newest first."
  defdelegate pending_habits(), to: Server.Dossier
  defdelegate pending_habits(workspace_id), to: Server.Dossier

  @doc "Every open workline's live status (stage, gate, blocking check) — the WORKLINES pane read."
  defdelegate workline_statuses(), to: Ledger, as: :statuses
  defdelegate workline_statuses(workspace_id), to: Ledger, as: :statuses

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
  Hard-delete a thread by id (the cockpit's `d` on a THREADS row) — loads fresh, so a stale
  row can't be acted on. `{:ok, thread}` · `{:error, :not_found}` · `{:error, :root_machine_thread}`.
  """
  def delete_thread(id) do
    case Server.Channel.thread(id) do
      nil -> {:error, :not_found}
      thread -> Server.Channel.delete_thread(thread)
    end
  end
end
