defmodule Server do
  @moduledoc """
  The boundary of the server system (enforced by the `:boundary` compiler — a violation is a
  compile warning, and the gate runs `--warnings-as-errors`, so reaching into a non-exported
  module fails `mise run check`).

  The exports below ARE the server's public surface — what a consumer may call. Everything else (`Repo`, the schemas' changesets, `Switchboard`, `Agent`, `Session`,
  the event/fact/issue internals) is this module's own business: reach for it from outside and
  the build says no. Widening the surface is a one-line diff HERE, which is the point — the
  surface creeps only on purpose, reviewed in this file's history.
  """

  use Boundary,
    deps: [],
    exports: [
      # The channel: threads, messages, the chorus — the one conversational API.
      Channel,
      # Pub/sub topics for live surfaces (announce stays internal callers').
      Bus,
      # Read models a surface renders: who's working, what's known, what's in scope.
      Staff,
      Board,
      Dossier,
      # Compositions: the workspaces context (rosters, repos, knobs).
      Workspaces,
      # Channels (UX slice 1b): workspace → channels → threads; create/move/delete + the row struct.
      Channels,
      ChannelRow,
      # The container tier: projects, the lightweight ticket tracker, notes — peer contexts to
      # Workspaces.
      Projects,
      Tickets,
      Notes,
      Presence,
      # Explicit thinking/idle presence (the office renders it; harnesses declare via MCP).
      Presence.Thinking,
      # The agent-to-agent consult (ask a peer; the answer is mirrored back).
      Consult,
      # Migration pre-flight and integrity checks.
      Doctor,
      # Identity minting for spawned harnesses (the server-citizen handshake).
      MCP.Spawn,
      # The arbiter behaviour (`Server.Arbiter.Tmux` implements it).
      Arbiter,
      # The crew behaviour (`Server.Crew.Tmux` implements it).
      Crew,
      # Structs read by consumers (pattern-matched, never changeset-built from outside).
      Thread,
      Message,
      # The BENCH boundary type (UX slice 5): a workspace's coworkers, handed out by
      # `Workspaces.bench/1` in place of the raw maps eight modules each used to interpret.
      Coworker,
      # What a coworker may do in a workspace — read by the profile materialiser.
      Policy,
      # The coworker-profile registry + materialiser, the harness drivers, leaf window names, the
      # tmux naming contract and the operator's settings file — what a coworker is spawned from.
      Profile,
      Profiles,
      Harness,
      Harness.Driver,
      Harness.ClaudeCode,
      LeafWindow,
      Tmux,
      OperatorConfig
    ]

  @doc "Staff a thread with an agent by handle — resolves the agent + thread and assigns."
  defdelegate assign_lead(thread_id, handle), to: Server.Channel

  @doc """
  The primary repo dir a thread's work lives in (thread→project→first repo) — the base a per-thread
  worktree or the office's lazygit opens against. Takes a thread id or struct.
  `{:ok, path}`, `{:error, :no_repo}`, or `{:error, :no_thread}`.
  """
  def repo_for_thread(%Server.Thread{} = thread), do: Server.Projects.repo_for_thread(thread)

  def repo_for_thread(thread_id) when is_integer(thread_id) do
    case Server.Channel.thread(thread_id) do
      nil -> {:error, :no_thread}
      thread -> Server.Projects.repo_for_thread(thread)
    end
  end

  @doc """
  Resolve a thread to the working dir its coworker (and a STACK-zoom lazygit) works in: its
  project's repo, then a lazily-ensured per-thread `git worktree` at `.worktrees/<name>` —
  `Server.Worktree.name_for/1`: the slug, else `t<id>`. Never the main tree (2026-09-08).
  `{:ok, path}`, `{:error, :no_repo | :no_thread | reason}`.
  """
  def worktree_for_thread(%Server.Thread{} = thread) do
    with {:ok, repo, name} <- repo_and_name(thread), do: Server.Worktree.ensure(repo, name)
  end

  def worktree_for_thread(thread_id) when is_integer(thread_id) do
    case Server.Channel.thread(thread_id) do
      nil -> {:error, :no_thread}
      thread -> worktree_for_thread(thread)
    end
  end

  # A thread's repo + its worktree name, the pair every worktree door resolves first.
  defp repo_and_name(thread) do
    with {:ok, repo} <- repo_for_thread(thread), do: {:ok, repo, Server.Worktree.name_for(thread)}
  end

  @doc """
  Open a workline from a title at `stage` (any-stage entry) — the tertius `open`/`spike`/`build`
  verbs' door (Slice 4D). `attrs` must carry `:title` + `:stage`; `:workspace_id`/`:project_id`/
  `:parent_thread_id` are optional. `{:ok, thread}` | `{:error, {:invalid_stage, s}}` | `{:error, cs}`.
  """
  def open_workline(%{title: title, stage: stage} = attrs),
    do: Server.Workline.open_titled(title, stage, Map.drop(attrs, [:title, :stage]))

  @doc """
  Approve a pending habit by id — loads fresh, so a stale row a surface rendered can't be
  acted on. `{:ok, habit}` · `{:error, :not_found}` · `{:error, changeset}`.
  """
  def approve_habit(id), do: with_habit(id, &Server.Dossier.approve_habit/1)

  @doc "Reject a pending habit by id — same load-fresh contract as approve."
  def reject_habit(id), do: with_habit(id, &Server.Dossier.reject_habit/1)

  defp with_habit(id, act) do
    case Server.Dossier.habit(id) do
      nil -> {:error, :not_found}
      habit -> act.(habit)
    end
  end

  @doc """
  Hard-delete a thread by id — loads fresh, so a stale row
  can't be acted on — and clean its worktree up when that is safe (`Server.Worktree.remove/2`:
  a clean checkout with nothing unmerged goes; anything else is kept and named). `{:ok, thread,
  :none | {:removed, path} | {:kept, reason}}` · `{:error, :not_found | :root_machine_thread}`.
  """
  def delete_thread(id) do
    case Server.Channel.thread(id) do
      nil ->
        {:error, :not_found}

      thread ->
        # resolve the checkout BEFORE the row goes — the path derives from the thread
        target = worktree_target(thread)

        with {:ok, deleted} <- Server.Channel.delete_thread(thread) do
          {:ok, deleted, cleanup_worktree(target)}
        end
    end
  end

  defp worktree_target(thread) do
    case repo_and_name(thread) do
      {:ok, repo, name} -> {repo, name}
      {:error, _} -> nil
    end
  end

  defp cleanup_worktree(nil), do: :none
  defp cleanup_worktree({repo, name}), do: Server.Worktree.remove(repo, name)
end
