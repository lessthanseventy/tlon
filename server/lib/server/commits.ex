defmodule Server.Commits do
  @moduledoc """
  The commit ↔ thread join (design: `docs/plans/2026-09-17-omarchy-atlas-steals.md` §4). A pane the
  server spawned commits with `Tlon-Thread: <id>` in the message — `scripts/git-hooks/
  prepare-commit-msg` stamps it from `TLON_THREAD` — so a thread's commits are one `git log --grep`
  over its repo, and the join rides every rewrite (rebase, amend, cherry-pick) with the message.
  Best-effort + honest like `Server.Workline.Artifacts.Git`: no repo, or a git fault, is an EMPTY
  section, never a crashed brief.
  """

  alias Server.Projects
  alias Server.Thread

  @trailer "Tlon-Thread"
  @cap 5

  @doc "A thread's commits, newest-first, cut like every brief section: `%{shown, more}`."
  def for_thread(%Thread{} = thread, cap \\ @cap) do
    with {:ok, repo} <- Projects.repo_for_thread(thread),
         {:ok, rows} <- list(repo, thread.id) do
      shown = Enum.take(rows, cap)
      %{shown: shown, more: length(rows) - length(shown)}
    else
      _ -> %{shown: [], more: 0}
    end
  end

  @doc """
  Every commit in `repo` carrying `Tlon-Thread: <thread_id>`, newest-first, across ALL refs — the
  worktree branches share the common dir, so a coworker's `work/<slug>` commits are here before
  they merge. `{:ok, [%{sha, subject, author, at}]}` or `{:error, reason}`.
  """
  def list(repo, thread_id) do
    args = ["log", "--all", "--grep=^#{@trailer}: #{thread_id}$", "--format=%H%x1f%s%x1f%an%x1f%aI"]

    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {out, 0} -> {:ok, out |> String.split("\n", trim: true) |> Enum.map(&row/1)}
      {out, _} -> {:error, out |> String.trim() |> String.slice(0, 200)}
    end
  end

  defp row(line) do
    [sha, subject, author, at] = String.split(line, "\x1f", parts: 4)
    %{sha: sha, subject: subject, author: author, at: at}
  end
end
