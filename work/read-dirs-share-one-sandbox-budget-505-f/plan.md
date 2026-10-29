# Plan — read dirs share one sandbox budget (#505, #582, #506)

Spec: `spec.md` beside this. Run tests with `~/projects/menard/bin/menard run test --in server <file>`; gate with `~/projects/menard/bin/menard run check --in server`. Edit Elixir with menard (`menard edit` / `clause`), not sed. Commit after each task, ending the message with `Co-Authored-By: <your model> <noreply@anthropic.com>`.

Files: `server/lib/server/sandbox_budget.ex` (new), `server/lib/server/projects.ex`, `server/lib/server/mcp/spawn.ex`, `server/test/server/projects_test.exs`, `server/test/server/profiles_test.exs`, `server/test/server/mcp/spawn_test.exs`.

Gotcha for every task: three existing tests use read-dir paths that do not exist (`projects_test.exs` ~164 `~/projects/ficciones`, ~179 `/p/mix_master`; `spawn_test.exs` ~246 `/p/b`, `/p/c`). Task 3's `File.dir?/1` check drops them, so those tests move to `@tag :tmp_dir` dirs (a `File.mkdir_p!(Path.join(d, ".git"))` each) in the same task.

## Task 1 — `nested_repos/1` counts only repos (#506)
RED (`projects_test.exs`, in the `read_dirs` describe; `nested_repos` is private, so test through `read_dirs_split` once it exists. For now make it `@doc false def nested_repos/1` and test it directly):
```elixir
    @tag :tmp_dir
    test "nested_repos counts repos only: an unreadable subdir's error line is not one", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join([dir, "r", ".git"]))
      locked = Path.join(dir, "locked")
      File.mkdir_p!(locked)
      File.chmod!(locked, 0o000)
      on_exit(fn -> File.chmod!(locked, 0o755) end)

      assert Projects.nested_repos(dir) == 1
    end
```
Red on main (the "Permission denied" line counts → 2). GREEN in `projects.ex`, replace `nested_repos/1`:
```elixir
  # `find -prune` never walks into a repo's own .git, which `**/.git` does (minutes on a big one).
  # Only `-print` lines count: stderr is merged in, and a "Permission denied" line is not a repo. The
  # exit code is ignored: a partial walk is a lower bound, so a checkout is never dropped on it alone.
  @doc false
  def nested_repos(dir) do
    {out, _} = System.cmd("find", [dir, "-name", ".git", "-prune", "-print"], stderr_to_stdout: true)
    out |> String.split("\n", trim: true) |> Enum.count(&String.ends_with?(&1, "/.git"))
  end
```
Done: `menard run test --in server test/server/projects_test.exs` green. Commit "projects: nested_repos counts only repos (#506)".

## Task 2 — one home for the budget numbers
No behaviour test needed beyond the compile; Task 4's test reads it. Create `server/lib/server/sandbox_budget.ex`:
```elixir
defmodule Server.SandboxBudget do
  @moduledoc """
  The bwrap argument budget a seat's sandbox spends. Claude Code mounts ~`args_per_repo` args per
  `.git` found under a write root (a read dir is one), and bwrap takes `bwrap_args` (#299, #455).
  `max_args` leaves headroom; `fixed_repos` are the checkouts every seat has (ficciones, tlon and its
  worktrees); `write_root_reserve` is what a seat's own scratch dir may hold. Read dirs share what is left.
  """

  @bwrap_args 9000
  @args_per_repo 45
  @fixed_repos 65
  @max_args 7500
  @write_root_reserve 40

  def bwrap_args, do: @bwrap_args
  def args_per_repo, do: @args_per_repo
  def fixed_repos, do: @fixed_repos
  def max_args, do: @max_args
  def write_root_reserve, do: @write_root_reserve

  @doc "Repos all of a project's read dirs may hold together: 166 - 65 - 40 = 61."
  def read_dir_repos, do: div(@max_args, @args_per_repo) - @fixed_repos - @write_root_reserve
end
```
If `mix compile` complains about the `:boundary` compiler, add the module the way sibling plain modules are (look at `Server.Projects`: no `use Boundary`, so none needed). Done: `menard run check --in server` compiles. Commit "sandbox budget: one home for the bwrap numbers".

## Task 3 — `read_dirs_split/1` spends the shared budget (#505, #506)
RED (`projects_test.exs`, uses the file's existing `workspace: ws` context as the "drop a checkout" test does):
```elixir
    @tag :tmp_dir
    test "read_dirs_split spends one budget across the list: skip what does not fit, keep later ones that do", %{
      workspace: ws,
      tmp_dir: dir
    } do
      dirs = for {n, count} <- [{"a", 30}, {"b", 30}, {"c", 10}], do: seed_dir(dir, n, count)
      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "shared", repos: [%{"name" => "own", "path" => "/p/own"} | named(dirs)]})
      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id, project_id: p.id})
      [a, b, c] = dirs

      assert Projects.read_dirs_split(t) == {[a, c], [b]}
      assert Projects.read_dirs(t) == [a, c]
    end

    @tag :tmp_dir
    test "a read dir that does not exist is not opened and not dropped", %{workspace: ws, tmp_dir: dir} do
      real = seed_dir(dir, "real", 1)
      repos = for {n, p} <- [{"own", "/p/own"}, {"gone", Path.join(dir, "gone")}, {"real", real}], do: %{"name" => n, "path" => p}
      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "gone", repos: repos})
      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id, project_id: p.id})

      assert Projects.read_dirs_split(t) == {[real], []}
    end
```
with test helpers at the bottom of the describe's module:
```elixir
  defp seed_dir(root, name, n) do
    dir = Path.join(root, name)
    for i <- 1..n, do: File.mkdir_p!(Path.join([dir, "r#{i}", ".git"]))
    dir
  end

  defp named(dirs), do: for(d <- dirs, do: %{"name" => Path.basename(d), "path" => d})
```
Run: red (`read_dirs_split/1` undefined). GREEN in `projects.ex`: delete `@max_nested_repos`, delete the `Task 1` `@doc false` (keep `nested_repos` public only if still used by tests; otherwise make it `defp` again and drop the Task 1 direct test in favour of a `read_dirs_split` case: one repo plus a `chmod 000` subdir stays kept), and replace `read_dirs/1`:
```elixir
  @doc """
  The thread's project's OTHER checkouts, `~`-expanded: what its coworker may read but not write
  (the harness opens them beside the worktree). Never the thread's own repo, never a scope glob, never
  a path that is not a directory; `[]` for a thread with no project. Claude Code makes a read dir a
  write root and bwrap mounts ~45 args per repo found under one, so the dirs together may hold
  `Server.SandboxBudget.read_dir_repos/0` repos: `read_dirs_split/1` keeps a dir while the running
  total fits and skips one that does not (a later, smaller one may still fit).
  """
  def read_dirs(thread), do: thread |> read_dirs_split() |> elem(0)

  @doc "`{kept, dropped}`: `read_dirs/1` and the dirs the shared budget left out, in list order."
  def read_dirs_split(%Server.Thread{project_id: pid} = thread) when not is_nil(pid) do
    own = with {:ok, path} <- repo_for_thread(thread), do: path

    dirs =
      for %{"path" => path} <- get(pid).repos || [],
          not String.contains?(path, "*"),
          dir = Path.expand(path),
          dir != own,
          File.dir?(dir),
          do: dir

    {kept, dropped, _used} =
      Enum.reduce(dirs, {[], [], 0}, fn dir, {kept, dropped, used} ->
        n = nested_repos(dir)

        if used + n <= Server.SandboxBudget.read_dir_repos(),
          do: {[dir | kept], dropped, used + n},
          else: {kept, [dir | dropped], used}
      end)

    {Enum.reverse(kept), Enum.reverse(dropped)}
  end

  def read_dirs_split(_thread), do: {[], []}
```
Then fix the "Gotcha" tests (tmp dirs for ficciones/mix_master; keep the "fat" test: 120 > 61 still drops it). Done: `menard run test --in server test/server/projects_test.exs` green. Commit "projects: read dirs spend one shared sandbox budget (#505)".

## Task 4 — the budget test sees read dirs (#505, #582)
In `profiles_test.exs`, the test at line ~56 ("a seat's write roots stay under the bwrap budget…"): alias `Server.SandboxBudget, Server.Projects, Server.Channel, Server.Workspaces`, add `@tag :tmp_dir` already present, and RED-first add before the seat loop:
```elixir
      # read dirs are write roots too (#505): 3 dirs of 30 repos each pass the old per-dir cap, sum 90 > 61
      {:ok, ws} = Workspaces.register(%{name: "budget-read"})
      read = for n <- ~w(ra rb rc), do: Path.join(home, "projects/#{n}")
      for d <- read, i <- 1..30, do: File.mkdir_p!(Path.join([d, "r#{i}", ".git"]))
      repos = for d <- read, do: %{"name" => Path.basename(d), "path" => d}
      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "budget-read", repos: [%{"name" => "own", "path" => "/p/own"} | repos]})
      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id, project_id: p.id})
      kept = Projects.read_dirs(t)
      read_count = kept |> Enum.map(&length(Path.wildcard(Path.join(&1, "**/.git"), match_dot: true))) |> Enum.sum()
```
and replace the assertion with
```elixir
        assert (count + read_count + SandboxBudget.fixed_repos()) * SandboxBudget.args_per_repo() <= SandboxBudget.max_args(),
               "#{seat}/#{archetype}: #{count} repos under ~ write roots + #{read_count} under read dirs"
```
(also replace the literal `40` in `seed_repos(home, ".cache/tlon-scratch/#{seat}", 40)` with `SandboxBudget.write_root_reserve()`, and update the comment above the test to point at `Server.SandboxBudget`). To see it RED, run it once against Task 3's parent (`git stash`-free: `git checkout HEAD~1 -- server/lib/server/projects.ex`, run, `git checkout HEAD -- server/lib/server/projects.ex`): all three dirs kept → (90 + 40 + 65) × 45 = 8775 > 7500. Green on HEAD. Done: `menard run test --in server test/server/profiles_test.exs` green. Commit "profiles test: the bwrap budget counts read dirs (#505, #582)".

## Task 5 — post the dropped dirs once at launch
RED (`spawn_test.exs`, next to the TLON_READ_DIRS test, tmp_dir with two dirs of 40 repos so the second is dropped):
```elixir
    @tag :tmp_dir
    test "read dirs the shared budget leaves out are posted once on the thread", %{tmp_dir: dir} do
      [a, b] = for n <- ~w(a b) do
        d = Path.join(dir, n)
        for i <- 1..40, do: File.mkdir_p!(Path.join([d, "r#{i}", ".git"]))
        d
      end

      {:ok, ws} = Server.Workspaces.register(%{name: "rd-drop"})
      repos = [%{"name" => "own", "path" => "/p/own"}, %{"name" => "a", "path" => a}, %{"name" => "b", "path" => b}]
      {:ok, p} = Server.Projects.register(%{workspace_id: ws.id, name: "drop", repos: repos})
      {:ok, thread} = Channel.open_thread(%{title: "rd", workspace_id: ws.id, project_id: p.id})

      assert {:ok, %{exports: ex}} = Spawn.join(thread.id, "codex")
      assert ex =~ ~s(TLON_READ_DIRS="#{a}")
      posts = for m <- Channel.messages(thread.id), m.body =~ "read dirs", do: m.body
      assert [body] = posts
      assert body =~ b
    end
```
(check the name of the messages reader with `grep -n "def messages" server/lib/server/channel.ex`; use whatever the sibling tests use.) GREEN in `spawn.ex`, replace `read_dirs_export/1`:
```elixir
  # The project's other repos, for the harness to open read-only beside the worktree. Dirs the shared
  # sandbox budget leaves out are named once on the thread, so the seat knows why they are not there.
  defp read_dirs_export(thread) do
    {kept, dropped} = Server.Projects.read_dirs_split(thread)

    if dropped != [] do
      Server.Channel.post(%{
        thread_id: thread.id,
        author: "tlon",
        kind: "notice",
        body:
          "read dirs left out (the seat's sandbox budget holds #{Server.SandboxBudget.read_dir_repos()} repos across them): " <>
            Enum.join(dropped, ", ")
      })
    end

    case kept do
      [] -> ""
      dirs -> "\nexport TLON_READ_DIRS=\"#{Enum.join(dirs, ":")}\""
    end
  end
```
Fix the existing `/p/b`, `/p/c` test to tmp dirs (Gotcha). Done: `menard run test --in server test/server/mcp/spawn_test.exs` green. Commit "spawn: name the read dirs the budget left out (#505)".

## Task 6 — docs and gate
Grep for stale prose: `grep -rn "max_nested_repos\|100 nested\|per-checkout" server docs AGENTS.md server/AGENTS.md`; update any hit to the shared budget in this commit. Then `menard run check --in server` (a coworker seat does not run `mise run check`); advance. Done when the check line reads ok with 0 failures and `grep -rn "7500\|\b65\b\|\b45\b" server/test/server/profiles_test.exs server/lib/server/projects.ex` finds no budget literals. Commit "docs: read dirs share one sandbox budget" only if something changed.

## Order and risk
Tasks 1→2→3→4→5→6, each independently committable. Risk: Task 5 posts on every launch of a project over budget (join runs per wake); accepted by the spec ("once at launch"). If that is noisy, dedupe is a follow-up, not this work.
