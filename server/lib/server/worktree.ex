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

  @doc """
  A thread's worktree name: its workline slug, else `t<id>`. Every thread a coworker joins gets a
  worktree (Andrew, 2026-09-08: "the minute it starts writing code it needs to be in a worktree"),
  and a slug only exists once a thread is promoted — `rename/3` moves the checkout across then.
  """
  def name_for(%{slug: slug}) when is_binary(slug) and slug != "", do: slug
  def name_for(%{id: id}), do: "t#{id}"

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

  @doc """
  Tear a thread's worktree down when its thread is deleted. The checkout goes when it is clean
  and its branch carries nothing unmerged; otherwise both stay and the reason names the branch —
  real work nobody asked to lose. `{:removed, path}` · `{:kept, reason}` · `:none` (never existed).
  """
  def remove(repo_path, slug) do
    wt = path(repo_path, slug)
    branch = branch(slug)

    cond do
      not File.exists?(Path.join(wt, ".git")) ->
        :none

      dirty?(wt) ->
        {:kept, "#{branch} has uncommitted changes at #{wt}"}

      unmerged?(repo_path, branch) ->
        {:kept, "#{branch} has unmerged commits — merge or delete it yourself"}

      true ->
        with {_out, 0} <- git(repo_path, ["worktree", "remove", wt]),
             {_out, 0} <- git(repo_path, ["branch", "-D", branch]) do
          {:removed, wt}
        else
          {out, _} -> {:kept, "git refused: #{String.slice(out, 0, 200)}"}
        end
    end
  end

  @doc """
  Promotion: the `t<id>` checkout becomes the slug's — `git worktree move` + `git branch -m`, so
  the branch the coworker has been committing to IS `work/<slug>`. `{:ok, new_path}` · `:none`
  (no source worktree) · `{:error, reason}`.
  """
  def rename(repo_path, from, to) do
    old = path(repo_path, from)
    new = path(repo_path, to)

    cond do
      not File.exists?(Path.join(old, ".git")) -> :none
      not Regex.match?(@slug, to_string(to)) -> {:error, :bad_slug}
      true -> do_rename(repo_path, old, new, branch(from), branch(to))
    end
  end

  defp do_rename(repo_path, old, new, from_branch, to_branch) do
    with {_out, 0} <- git(repo_path, ["worktree", "move", old, new]),
         {_out, 0} <- git(repo_path, ["branch", "-m", from_branch, to_branch]) do
      {:ok, new}
    else
      {out, _} -> {:error, "git refused: #{String.slice(out, 0, 200)}"}
    end
  end

  defp dirty?(wt), do: match?({out, 0} when out != "", git(wt, ["status", "--porcelain"]))

  # Commits on the branch that no OTHER branch reaches — the "unmerged" that matters for a delete.
  # (`--not --branches` would include the branch itself; excluding it first makes the set honest.)
  defp unmerged?(repo_path, branch) do
    case git(repo_path, ["log", "--oneline", branch, "--not", "--exclude=#{branch}", "--branches"]) do
      {out, 0} -> String.trim(out) != ""
      _ -> true
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
      {_out, 0} ->
        link_deps(repo_path, wt)
        {:ok, wt}

      {out, _} ->
        {:error, "git worktree add refused: #{String.slice(out, 0, 200)}"}
    end
  end

  # Dependency dirs are gitignored, so a fresh worktree has none and the first `mix compile` /
  # `npm` there is minutes (survey §1: CCManager's .worktreeinclude, parallel-code's symlinks).
  # Share them by SYMLINK from the main tree — `deps` and `node_modules` are content-addressed by
  # their lockfiles and safe to share; `_build` is NOT (compiled artifacts of a different branch),
  # so each worktree builds its own. Best-effort: a missing dir in the main tree is skipped.
  @shared_deps ["deps", "node_modules", "server/deps", "console/deps", "modules/desktop/shell/node_modules"]

  defp link_deps(repo_path, wt) do
    for rel <- @shared_deps,
        src = Path.join(repo_path, rel),
        dst = Path.join(wt, rel),
        File.dir?(src),
        not File.exists?(dst) do
      File.mkdir_p!(Path.dirname(dst))
      File.ln_s(src, dst)
    end

    :ok
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
