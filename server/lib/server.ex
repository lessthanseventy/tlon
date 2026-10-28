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

  require Logger

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
  `Server.Worktree.name_for/1`: the slug, else `t<id>`. Never the main tree (2026-09-08). The
  checkout is marked with the thread (`Server.Worktree.mark_thread/2`), which its commits are stamped with.
  `{:ok, path}`, `{:error, :no_repo | :no_thread | reason}`.
  """
  def worktree_for_thread(%Server.Thread{} = thread) do
    with {:ok, repo, name} <- repo_and_name(thread),
         {:ok, wt} <- Server.Worktree.ensure(repo, name) do
      Server.Worktree.mark_thread(wt, thread.id)
      {:ok, wt}
    end
  end

  def worktree_for_thread(thread_id) when is_integer(thread_id) do
    case Server.Channel.thread(thread_id) do
      nil -> {:error, :no_thread}
      thread -> worktree_for_thread(thread)
    end
  end

  @doc """
  A waking seat's checkout, brought up to origin/main when it holds no work of its own
  (`Server.Worktree.catch_up/1`), what it could not move told to the thread. Only a spawn calls it:
  `worktree_for_thread/1` is hit mid-turn by tools and gates, where a move would land under a live pane.
  """
  def catch_up_worktree(%Server.Thread{} = thread, wt) do
    wt |> Server.Worktree.catch_up() |> tell_catch_up(wt, thread)
  end

  @doc """
  Bring a thread's checkout onto origin/main now (`Server.Worktree.bring_to_main/1`), the result told
  to the thread as a notice. Unlike `catch_up_worktree/2` this is asked for, so every outcome is posted,
  not once per state. Returns `bring_to_main/1`'s result, or `{:error, why}` when the thread has no checkout.
  """
  def bring_branch_to_main(%Server.Thread{} = thread) do
    with {:ok, wt} <- worktree_for_thread(thread) do
      result = Server.Worktree.bring_to_main(wt)
      Server.Channel.post(%{thread_id: thread.id, author: "tlon", kind: "notice", body: moved_text(result)})
      result
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

  # What a wake's catch-up left to say: a checkout it could not move, once per state (a lobby wakes
  # often), so the thread knows why its checkout is behind main. A notice: a bare chat post is
  # addressed to the thread's lead and wakes or spawns them for a status line.
  defp tell_catch_up({:ahead, n}, wt, thread) do
    # own commits on top of main are a workline's normal state: only a main that moved on is news
    case Server.Worktree.moved_past(wt) do
      {:ok, tip} ->
        say_once(
          wt,
          thread,
          "ahead:#{tip}:#{n}",
          "checkout left where it is: #{n} commit#{if n == 1, do: "", else: "s"} of its own beyond origin/main"
        )

      :no ->
        :ok
    end
  end

  # A checkout that caught up forgets what it reported, so the next stall is news again.
  defp tell_catch_up(moved, wt, _thread) when moved in [:moved, :level] do
    Server.Worktree.report_once?(wt, "level")
    :ok
  end

  defp tell_catch_up({:error, why}, wt, thread) do
    Logger.warning("catch-up of #{wt} to origin/main failed: #{inspect(why)}")
    say_once(wt, thread, "error", "checkout could not be moved to origin/main: #{inspect(why)}")
  end

  defp tell_catch_up(:dirty, wt, thread),
    do: say_once(wt, thread, "dirty", "checkout left where it is: uncommitted changes, so not moved to origin/main")

  defp tell_catch_up(_, _wt, _thread), do: :ok

  defp say_once(wt, thread, key, body) do
    if Server.Worktree.report_once?(wt, key),
      do: Server.Channel.post(%{thread_id: thread.id, author: "tlon", kind: "notice", body: body})

    :ok
  end

  defp moved_text(:moved), do: "checkout fast-forwarded to origin/main"
  defp moved_text(:level), do: "checkout already on origin/main"

  defp moved_text({:rebased, n}),
    do: "checkout rebased onto origin/main (#{n} commit#{if n == 1, do: "", else: "s"} replayed)"

  defp moved_text({:refused, why}), do: "checkout not moved: #{why}"
  defp moved_text({:error, why}), do: "checkout could not be moved to origin/main: #{inspect(why)}"
end
