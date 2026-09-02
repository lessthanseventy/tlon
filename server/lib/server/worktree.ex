defmodule Server.Worktree do
  @moduledoc """
  Per-thread git worktrees (Slice 4). A workline thread's code lives on branch `work/<slug>`;
  this lazily materializes an isolated CHECKOUT of that branch at `<repo>/.worktrees/<slug>`,
  so parallel crew edit without stepping on each other's working tree. git follows the thread.

  Deliberately DISTINCT from the artifact-docs dir `work/<slug>/` (`Server.Workline.Scribe`'s
  committed intent/spec/plan/review, which live in the MAIN tree) — a real `git worktree` there
  would collide, so the checkout goes to `.worktrees/<slug>` instead. `.worktrees/` is ignored
  repo-locally through `.git/info/exclude`, never a committed `.gitignore` — the dir is
  tool-managed, not project state.

  Best-effort + honest, like `Server.Workline.Artifacts.Git`: a git fault is `{:error, reason}`,
  never a raise, so a broken repo degrades gracefully instead of wedging the cockpit.
  """

  # The slug names filesystem paths — same closed charset the workline enforces (Server.Thread),
  # re-checked here so a bad slug can never traverse out of `.worktrees/`.
  @slug ~r/\A[a-z0-9][a-z0-9-]*\z/

  @doc "The branch a thread's code lives on. Matches `Server.Workline.Artifacts.Git`."
  def branch(slug), do: "work/#{slug}"

  @doc "Where the thread's worktree checkout lives (pure) — `<repo>/.worktrees/<slug>`."
  def path(repo_path, slug), do: Path.join([repo_path, ".worktrees", slug])

  @doc """
  Lazily ensure the worktree exists. Idempotent — an existing checkout returns its path untouched.
  Creates branch `work/<slug>` off HEAD when absent, reuses it when present. `{:ok, abs_path}` or
  `{:error, :bad_slug | :not_a_repo | reason}`.
  """
  def ensure(repo_path, slug) do
    cond do
      not Regex.match?(@slug, to_string(slug)) -> {:error, :bad_slug}
      not git_repo?(repo_path) -> {:error, :not_a_repo}
      true -> do_ensure(repo_path, slug)
    end
  end

  # -- helpers --------------------------------------------------------------

  defp do_ensure(repo_path, slug) do
    wt = path(repo_path, slug)

    # A linked worktree carries a `.git` FILE (`gitdir: …`), not a dir — presence is enough.
    if File.exists?(Path.join(wt, ".git")) do
      {:ok, wt}
    else
      ignore_worktrees(repo_path)
      add(repo_path, wt, slug)
    end
  end

  defp add(repo_path, wt, slug) do
    branch = branch(slug)

    args =
      if branch_exists?(repo_path, branch),
        do: ["worktree", "add", wt, branch],
        else: ["worktree", "add", "-b", branch, wt]

    case git(repo_path, args) do
      {_out, 0} -> {:ok, wt}
      {out, _} -> {:error, "git worktree add refused: #{String.slice(out, 0, 200)}"}
    end
  end

  # Repo-local ignore of the tool-managed checkout dir — `.git/info/exclude`, not a tracked
  # `.gitignore`, so the project's committed state is never touched. Idempotent.
  defp ignore_worktrees(repo_path) do
    with {dir, 0} <- git(repo_path, ["rev-parse", "--git-common-dir"]) do
      exclude = Path.join([Path.expand(String.trim(dir), repo_path), "info", "exclude"])
      append_line_once(exclude, ".worktrees/")
    end

    :ok
  end

  defp append_line_once(file, line) do
    current =
      case File.read(file) do
        {:ok, c} -> c
        _ -> ""
      end

    if !String.contains?(current, line) do
      File.mkdir_p!(Path.dirname(file))
      sep = if current == "" or String.ends_with?(current, "\n"), do: "", else: "\n"
      File.write!(file, current <> sep <> line <> "\n")
    end
  end

  defp branch_exists?(repo_path, branch) do
    match?({_out, 0}, git(repo_path, ["rev-parse", "--verify", "--quiet", branch]))
  end

  defp git_repo?(repo_path) do
    File.dir?(repo_path) and match?({_out, 0}, git(repo_path, ["rev-parse", "--git-dir"]))
  end

  defp git(repo_path, args), do: System.cmd("git", ["-C", repo_path | args], stderr_to_stdout: true)
end
