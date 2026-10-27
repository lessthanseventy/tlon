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
  never a raise, so a broken repo degrades gracefully instead of wedging its caller.
  """

  # The slug names filesystem paths — same closed charset the workline enforces (Server.Thread),
  # re-checked here so a bad slug can never traverse out of `.worktrees/`.
  @slug ~r/\A[a-z0-9][a-z0-9-]*\z/

  # A module's installed deps, keyed by the lockfile that pins them.
  @deps %{"mix.lock" => ["deps", "_build"], "bun.lock" => ["node_modules"]}

  @doc """
  The branch a thread's code lives on. Matches `Server.Workline.Artifacts.Git`.

      iex> Server.Worktree.branch("redis-cache")
      "work/redis-cache"
  """
  def branch(slug), do: "work/#{slug}"

  @doc """
  A thread's worktree name: its workline slug, else `t<id>`. Every thread a coworker joins gets a
  worktree (Andrew, 2026-09-08: "the minute it starts writing code it needs to be in a worktree"),
  and a slug only exists once a thread is promoted — `rename/3` moves the checkout across then.

      iex> Server.Worktree.name_for(%{id: 9, slug: "redis-cache"})
      "redis-cache"

      iex> Server.Worktree.name_for(%{id: 9, slug: nil})
      "t9"
  """
  def name_for(%{slug: slug}) when is_binary(slug) and slug != "", do: slug
  def name_for(%{id: id}), do: "t#{id}"

  @doc """
  Where the thread's worktree checkout lives (pure) — `<repo>/.worktrees/<slug>`.

      iex> Server.Worktree.path("/r", "redis-cache")
      "/r/.worktrees/redis-cache"
  """
  def path(repo_path, slug), do: Path.join([repo_path, ".worktrees", slug])

  @doc """
  Lazily ensure the worktree exists. Idempotent — an existing checkout returns its path untouched.
  Creates branch `work/<slug>` off `main` (HEAD where there is none) when absent, reuses it when
  present. `{:ok, abs_path}` or `{:error, :bad_slug | :not_a_repo | reason}`.
  """
  def ensure(repo_path, slug) do
    cond do
      not Regex.match?(@slug, to_string(slug)) -> {:error, :bad_slug}
      not git_repo?(repo_path) -> {:error, :not_a_repo}
      true -> do_ensure(repo_path, slug)
    end
  end

  @doc """
  Bring a thread's checkout up to origin/main when it holds no work of its own: on a branch, clean,
  with HEAD an ancestor of origin/main, `merge --ff-only`. Never fetches (the root's refs are shared
  and KeepUp keeps origin/main fresh). `:moved | :level | :detached | :dirty | {:ahead, n}` (own
  commits, left alone) `| {:error, why}`; a checkout with no origin/main is `:level`.
  """
  def catch_up(wt) do
    case git(wt, ["rev-parse", "--abbrev-ref", "HEAD"]) do
      {"HEAD\n", 0} -> :detached
      {_, 0} -> if branch_exists?(wt, "refs/remotes/origin/main"), do: catch_up_branch(wt), else: :level
      {out, _} -> {:error, String.slice(out, 0, 200)}
    end
  end

  @doc """
  Whether `key` is news for this checkout: true the first time it is seen, false until a different
  key replaces it. Held in the checkout's git dir (`tlon-reported`), so a report repeats on no wake.
  """
  def report_once?(wt, key) do
    case git(wt, ["rev-parse", "--absolute-git-dir"]) do
      {dir, 0} ->
        file = Path.join(String.trim(dir), "tlon-reported")

        if File.read(file) == {:ok, key <> "\n"} do
          false
        else
          File.write(file, key <> "\n")
          true
        end

      _ ->
        true
    end
  end

  @doc """
  Record the thread a checkout belongs to in its own git dir (`tlon-thread`). The
  prepare-commit-msg hook stamps that thread rather than the pane's, so a commit made in a
  workline's checkout from a pane bound elsewhere (the lobby) still joins the workline's thread.
  """
  @spec mark_thread(String.t(), integer()) :: :ok | {:error, term()}
  def mark_thread(wt, thread_id) do
    case git(wt, ["rev-parse", "--absolute-git-dir"]) do
      {dir, 0} -> File.write(Path.join(String.trim(dir), "tlon-thread"), "#{thread_id}\n")
      {out, _} -> {:error, String.trim(out)}
    end
  end

  @doc """
  Tear a thread's worktree down when its thread is deleted. The checkout goes when it is clean
  and its branch carries nothing unmerged; otherwise both stay and the reason names the branch —
  real work nobody asked to lose. `{:removed, path}` · `{:kept, reason}` · `:none` (never existed).
  """
  def remove(repo_path, slug) do
    wt = path(repo_path, slug)

    cond do
      not File.exists?(Path.join(wt, ".git")) ->
        :none

      reason = holds(repo_path, slug) ->
        {:kept, reason}

      true ->
        branch = checked_out(repo_path, slug)

        with {_out, 0} <- git(repo_path, ["worktree", "remove", wt]),
             {_out, 0} <- delete_branch(repo_path, branch) do
          {:removed, wt}
        else
          {out, _} -> {:kept, "git refused: #{String.slice(out, 0, 200)}"}
        end
    end
  end

  @doc """
  Take down a checkout whose work was closed on purpose (superseded or abandoned,
  `Server.Channel.close_as/2`) or that the operator took down from the inbox — keeping its work: a
  rebase, merge or cherry-pick left half done is aborted (its commits stay; conflict resolutions in
  progress do not), what is uncommitted is committed on the branch as work in progress, and a
  detached checkout's commits get a `rescued/<slug>-<sha>` branch. The branch stays, so all of it
  can still be found. `{:removed, path}` · `{:kept, reason}` when git refuses · `:none`.
  """
  def retire(repo_path, slug) do
    wt = path(repo_path, slug)

    if File.exists?(Path.join(wt, ".git")) do
      with :ok <- keep_work(wt, slug),
           {_out, 0} <- git(repo_path, ["worktree", "remove", "--force", wt]) do
        {:removed, wt}
      else
        {:kept, _} = kept -> kept
        {out, _} -> {:kept, "git refused: #{String.slice(out, 0, 200)}"}
      end
    else
      :none
    end
  end

  @doc "Why a checkout must stay — uncommitted changes, or commits no other branch has — or nil."
  @spec holds(String.t(), String.t()) :: String.t() | nil
  def holds(repo_path, slug) do
    branch = checked_out(repo_path, slug)

    cond do
      dirty?(path(repo_path, slug)) -> "#{branch} has uncommitted changes at #{path(repo_path, slug)}"
      unmerged?(repo_path, branch) -> "#{branch} has unmerged commits — merge or delete it yourself"
      true -> nil
    end
  end

  @doc "Why closing the thread would strand its checkout — `holds/2`, but nil when no checkout exists."
  @spec stranded(String.t(), String.t()) :: String.t() | nil
  def stranded(repo_path, slug) do
    if File.exists?(Path.join(path(repo_path, slug), ".git")), do: holds(repo_path, slug)
  end

  @doc "The checkouts under `repo_path`'s `.worktrees/`, by name."
  @spec names(String.t()) :: [String.t()]
  def names(repo_path) do
    case File.ls(Path.join(repo_path, ".worktrees")) do
      {:ok, names} -> Enum.filter(names, &File.exists?(Path.join(path(repo_path, &1), ".git")))
      _ -> []
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

  # what the checkout has out — a branch made by hand need not be work/<slug>; detached, its commit
  defp checked_out(repo_path, slug) do
    wt = path(repo_path, slug)

    case git(wt, ["symbolic-ref", "-q", "--short", "HEAD"]) do
      {out, 0} ->
        String.trim(out)

      _ ->
        case git(wt, ["rev-parse", "HEAD"]) do
          {sha, 0} -> String.trim(sha)
          _ -> branch(slug)
        end
    end
  end

  # never the main checkout's own branch, nor a commit (a detached checkout has no branch to drop)
  defp delete_branch(repo_path, branch) do
    {main, _} = git(repo_path, ["symbolic-ref", "-q", "--short", "HEAD"])

    if branch != String.trim(main) and branch_exists?(repo_path, "refs/heads/#{branch}"),
      do: git(repo_path, ["branch", "-D", branch]),
      else: {"", 0}
  end

  defp dirty?(wt), do: match?({out, 0} when out != "", git(wt, ["status", "--porcelain"]))

  defp forward(wt) do
    with {head, 0} <- git(wt, ["rev-parse", "HEAD"]),
         {main, 0} <- git(wt, ["rev-parse", "origin/main"]) do
      if head == main, do: :level, else: merge_ff(wt)
    else
      {out, _} -> {:error, String.slice(out, 0, 200)}
    end
  end

  defp merge_ff(wt) do
    case git(wt, ["merge", "--ff-only", "-q", "origin/main"]) do
      {_, 0} -> :moved
      {out, _} -> {:error, String.slice(out, 0, 200)}
    end
  end

  defp own_commits(wt) do
    case git(wt, ["rev-list", "--count", "origin/main..HEAD"]) do
      {n, 0} -> {:ahead, n |> String.trim() |> String.to_integer()}
      {out, _} -> {:error, String.slice(out, 0, 200)}
    end
  end

  # Commits on the branch that no OTHER branch reaches — the "unmerged" that matters for a delete.
  # (`--not --branches` would include the branch itself; excluding it first makes the set honest.)
  # by change, not by hash: a rebase merge lands the same change on main as a new commit, so a
  # branch is unmerged only while it holds a change ("+" in git cherry) the main checkout lacks
  # against origin's main where there is one: what GitHub merged is merged, however far this checkout
  # lags behind it
  defp unmerged?(repo_path, branch) do
    base = if branch_exists?(repo_path, "refs/remotes/origin/main"), do: "origin/main", else: "HEAD"

    case git(repo_path, ["cherry", base, branch]) do
      {out, 0} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.starts_with?(&1, "+"))
        |> Enum.map(fn "+ " <> sha -> String.trim(sha) end)
        |> case do
          [] -> false
          shas -> not landed?(repo_path, base, branch, shas)
        end

      _ ->
        true
    end
  end

  # A rebase merge can fold a commit's files into a neighbouring commit, and a later commit can
  # rewrite an earlier one's file, so no single commit need match main. The branch has landed when
  # its TIP is identical to main over every file its "+" commits touched; a file main changed after
  # the landing still reads unmerged.
  defp landed?(repo_path, base, tip, shas) do
    results = Enum.map(shas, &git(repo_path, ["diff-tree", "-z", "--no-commit-id", "--name-only", "-r", &1]))

    with true <- Enum.all?(results, &match?({_, 0}, &1)),
         files when files != [] <-
           results |> Enum.flat_map(fn {out, 0} -> String.split(out, "\0", trim: true) end) |> Enum.uniq() do
      match?({_, 0}, git(repo_path, ["diff", "--quiet", tip, base, "--" | files]))
    else
      _ -> false
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

      with {:ok, wt} <- add(repo_path, wt, slug) do
        seed_deps(repo_path, wt)
        {:ok, wt}
      end
    end
  end

  # A fresh checkout starts with the main checkout's installed deps wherever its lockfile is the
  # same — fetching and compiling them again would only reproduce them; a changed lockfile is left
  # to install. Copy-on-write where the filesystem has it (btrfs, xfs), a plain copy otherwise, never
  # hard links: a build in the worktree rewrites files in place and would corrupt the main's.
  defp seed_deps(repo_path, wt) do
    for {lock, dirs} <- @deps,
        main_lock <-
          Path.wildcard(Path.join([repo_path, "*", lock])) ++ Path.wildcard(Path.join([repo_path, "*/*", lock])),
        rel = Path.relative_to(Path.dirname(main_lock), repo_path),
        not String.starts_with?(rel, ".worktrees"),
        File.read(Path.join([wt, rel, lock])) == File.read(main_lock),
        dir <- dirs,
        src = Path.join([repo_path, rel, dir]),
        dst = Path.join([wt, rel, dir]),
        File.dir?(src) and not File.exists?(dst) do
      copy_tree(src, dst)
    end

    :ok
  end

  defp copy_tree(src, dst) do
    case System.cmd("cp", ["-a", "--reflink=auto", src, dst], stderr_to_stdout: true) do
      {_, 0} -> :ok
      # BSD cp (macOS) has no --reflink
      _ -> System.cmd("cp", ["-Rp", src, dst], stderr_to_stdout: true)
    end
  end

  defp add(repo_path, wt, slug) do
    branch = branch(slug)

    # a new branch starts from what was approved and merged — origin/main — not whatever the checkout
    # is on: local main carries the server's own commits and a side branch's would ride along
    base =
      cond do
        branch_exists?(repo_path, "origin/main") -> ["origin/main"]
        branch_exists?(repo_path, "main") -> ["main"]
        true -> []
      end

    args =
      if branch_exists?(repo_path, branch),
        do: ["worktree", "add", wt, branch],
        else: ["worktree", "add", "-b", branch, wt | base]

    case git(repo_path, args) do
      {_out, 0} ->
        link_deps(repo_path, wt)
        {:ok, wt}

      {out, _} ->
        if File.dir?(wt) and not File.exists?(Path.join(wt, ".git")),
          do: {:error, {:not_a_checkout, wt}},
          else: {:error, "git worktree add refused: #{String.slice(out, 0, 200)}"}
    end
  end

  # Only what nothing in a worktree can write is shared by symlink: the desktop shell's
  # node_modules is links into the read-only nix store, with no lockfile for `seed_deps` to match.
  # Mutable deps are seeded as copies, or a `mix deps.update` on one branch rewrites every checkout's.
  @shared_deps ["modules/desktop/shell/node_modules"]

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

  defp git(repo_path, args),
    do: Application.get_env(:server, :git_cmd, &System.cmd/3).("git", ["-C", repo_path | args], stderr_to_stdout: true)

  # nothing the checkout holds may go with it: half-done operations undone, edits committed, a
  # detached HEAD named
  defp keep_work(wt, slug) do
    for op <- ~w(rebase merge cherry-pick), do: git(wt, [op, "--abort"])

    with :ok <- commit_dirty(wt),
         do: name_detached(wt, slug)
  end

  defp commit_dirty(wt) do
    if dirty?(wt) do
      with {_, 0} <- git(wt, ["add", "-A"]),
           {_, 0} <-
             git(wt, [
               "-c",
               "user.name=tlon",
               "-c",
               "user.email=tlon@localhost",
               "-c",
               "commit.gpgsign=false",
               "commit",
               "--no-verify",
               "-qm",
               "wip: kept when its checkout was taken down"
             ]) do
        :ok
      else
        {out, _} -> {:kept, "its uncommitted work could not be committed: #{String.slice(out, 0, 200)}"}
      end
    else
      :ok
    end
  end

  defp name_detached(wt, slug) do
    case git(wt, ["symbolic-ref", "-q", "HEAD"]) do
      {_, 0} ->
        :ok

      _ ->
        {sha, _} = git(wt, ["rev-parse", "--short", "HEAD"])

        case git(wt, ["branch", "-f", "rescued/#{slug}-#{String.trim(sha)}", "HEAD"]) do
          {_, 0} -> :ok
          {out, _} -> {:kept, "its detached commits could not be named: #{String.slice(out, 0, 200)}"}
        end
    end
  end

  defp catch_up_branch(wt) do
    cond do
      dirty?(wt) -> :dirty
      match?({_, 0}, git(wt, ["merge-base", "--is-ancestor", "HEAD", "origin/main"])) -> forward(wt)
      true -> own_commits(wt)
    end
  end
end
