# Plan — #463 a server-run "bring my thread branch onto origin/main" tool

Goal: a seat whose sandbox can't rewrite `.claude/settings.json` (bind mount) calls one MCP tool,
`catch_up_branch`; the service (outside the sandbox) moves the thread checkout and tells the thread.

Three cases, all pinned by tests (Task 1): fast-forward (clean, behind) · `rebase origin/main`
(own commits, clean tree) · refuse with a reason (dirty, mid-rebase/merge, detached). A conflicting
rebase is aborted so the branch is exactly as it was.

Assumptions (say so if wrong): no `git fetch` — like `catch_up/1`, it trusts the shared refs KeepUp keeps
fresh; "level" is reported as already up to date. Out of scope: #655.

## Task 1 — `Server.Worktree.bring_to_main/1` (test first)
Files: `server/lib/server/worktree.ex`, `server/test/server/worktree_test.exs`.

Add a `describe "bring_to_main/1"` after the `catch_up/1` describe, reusing its `setup` shape (bare
`origin`, `Worktree.ensure(repo, "x")`, `advance`, `head`). Tests (each red first):
1. behind + clean → `:moved`, `head(wt) == head(repo)`, `NEW` exists.
2. own commit + main moved → `{:rebased, 1}`; `HEAD~1 == origin/main`; `MINE` and `NEW` both exist;
   branch name unchanged (`rev-parse --abbrev-ref HEAD` = `work/x`).
3. already level / own commits on current main → `:level` / `{:rebased, 0}`-free: assert `:level` when
   `HEAD == origin/main`, and `{:ahead, n}`-style no-op → `:level` when main hasn't moved past the branch.
4. dirty (untracked file `SCRATCH`, and separately a modified tracked file) → `{:refused, reason}` with
   reason =~ "uncommitted"; HEAD unchanged; file still there. Do this with main moved AND own commit so a
   wrong implementation would rebase.
5. mid-rebase: make a conflicting commit on main and in wt, run `git rebase origin/main` in wt by hand
   (stops on conflict) → then `bring_to_main` → `{:refused, reason}` reason =~ "rebase"; state untouched.
   (A clean-tree stopped rebase is why the check reads `git rev-parse --git-path rebase-merge|rebase-apply|MERGE_HEAD|CHERRY_PICK_HEAD`, not just `status`.)
6. detached HEAD → `{:refused, reason}` reason =~ "detached".
7. conflicting rebase (same file edited in wt and main, clean tree) → `{:refused, reason}` reason =~ "conflict";
   afterwards `status --porcelain` empty, HEAD == pre-call HEAD, no `.git/rebase-merge` (aborted).
8. no origin/main → `:level`.

Implementation (`worktree.ex`, near `catch_up/1`):
```elixir
@doc """
Bring a thread's checkout onto origin/main on request (the seat's sandbox cannot: its settings file is a
bind mount). `catch_up/1`'s fast-forward, plus `rebase origin/main` for a branch with commits of its own.
Never fetches. `:moved | :level | {:rebased, n}` (n own commits replayed) `| {:refused, reason}` (dirty,
half-done git operation, detached, or a conflict — the rebase is aborted, the branch as it was) `| {:error, why}`.
"""
def bring_to_main(wt) do
  with :ok <- refuse_half_done(wt) do
    case catch_up(wt) do
      :detached -> {:refused, "HEAD is detached — check out the thread branch first"}
      :dirty -> {:refused, "uncommitted changes — commit or discard them first, then ask again"}
      {:ahead, n} -> rebase_onto_main(wt, n)
      other -> other
    end
  end
end

defp refuse_half_done(wt) do
  half =
    Enum.find(~w(rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD), fn name ->
      match?({p, 0} when p != "", git(wt, ["rev-parse", "--git-path", name])) and
        File.exists?(Path.expand(String.trim(elem(git(wt, ["rev-parse", "--git-path", name]), 0)), wt))
    end)

  if half, do: {:refused, "a #{half} is in progress — finish or abort it first"}, else: :ok
end

defp rebase_onto_main(wt, n) do
  if moved_past(wt) == :no do
    :level
  else
    case git(wt, ["rebase", "--quiet", "--no-update-refs", "origin/main"]) do
      {_, 0} -> {:rebased, n}
      {out, _} ->
        git(wt, ["rebase", "--abort"])
        {:refused, "rebase onto origin/main hit a conflict, aborted — the branch is as it was: #{String.slice(out, 0, 300)}"}
    end
  end
end
```
(`refuse_half_done` first: `catch_up/1` on a mid-conflict tree would say `:dirty` for a conflict but `{:ahead,_}`
for a clean stopped rebase — which must not be rebased again. Simplify the `find` to a small helper if it reads badly.)
Note `--no-update-refs` as `Workline.Merge.rebase_in` does: the machine's git config sets `rebase.updateRefs`.
Verify: `~/projects/menard/bin/menard run test --in server test/server/worktree_test.exs` → ok, 0 failures.
Commit: `bring_to_main: fast-forward, rebase or refuse a thread checkout (#463)`.

## Task 2 — facade `Server.bring_branch_to_main/1` + thread notice (test first)
Files: `server/lib/server.ex`, `server/test/server/worktree_test.exs` (the `Server.catch_up_worktree` tests live there, ~L190).
Test: with the thread/ws/project setup those tests use — behind → `{:ok, :moved}` and a `kind: "notice"` message
from "tlon" on the thread =~ "origin/main"; own commit + main moved → `{:ok, {:rebased, 1}}`, notice =~ "1 commit";
dirty → `{:refused, r}` and a notice =~ "uncommitted". Each asserted by reading `Server.Channel.thread_messages(thread)`.
Implement next to `catch_up_worktree/2`:
```elixir
@doc "Bring a thread's checkout onto origin/main now (`Server.Worktree.bring_to_main/1`), the result told to the thread. Unlike `catch_up_worktree/2` this is asked for, so every outcome is posted, not once."
def bring_branch_to_main(%Server.Thread{} = thread) do
  with {:ok, wt} <- worktree_for_thread(thread) do
    result = Server.Worktree.bring_to_main(wt)
    Server.Channel.post(%{thread_id: thread.id, author: "tlon", kind: "notice", body: moved_text(result)})
    result
  end
end
```
`moved_text/1`: `:moved` "checkout fast-forwarded to origin/main" · `:level` "checkout already on origin/main" ·
`{:rebased, n}` "checkout rebased onto origin/main (#{n} commit(s) replayed)" · `{:refused, why}` "checkout not moved: #{why}" ·
`{:error, why}` "checkout could not be moved to origin/main: #{inspect why}". Return `{:ok, result}`/`{:refused,_}`/`{:error,_}` as the tool needs (keep it: pass the raw result; the tool maps it).
Verify: same test file, ok. Commit: `Server.bring_branch_to_main/1: the move, told to the thread (#463)`.

## Task 3 — MCP tool `catch_up_branch` (test first)
Files: new `server/lib/server/mcp/tools/catch_up_branch.ex`, `server/lib/server/mcp/endpoint.ex` (after the `push_branch` component, L105),
`server/test/server/mcp/server_test.exs` (add `"catch_up_branch"` to the tool-list assertion near L157, and a call test).
Tool, modelled on `PushBranch` (`use Server.MCP.Tool`, `acting_thread(params, frame)` so a lead may pass `thread_id`):
```elixir
defmodule Server.MCP.Tool.CatchUpBranch do
  @moduledoc """
  Bring the caller's thread checkout onto origin/main, run by the service because a seat's sandbox cannot
  (`.claude/settings.json` is a bind mount, so its own `git rebase` dies half-way). Fast-forwards a clean branch
  behind main, rebases one with commits of its own, refuses a dirty or half-done checkout with the reason
  (`Server.Worktree.bring_to_main/1`). Push afterwards with push_branch.
  """
  use Server.MCP.Tool
  schema do
    field :thread_id, :integer, description: "The workline you lead, when your session is bound to another thread (e.g. the lobby)"
  end
  @impl true
  def execute(params, frame) do
    with %Server.Thread{} = thread <- acting_thread(params, frame) do
      case Server.bring_branch_to_main(thread) do
        {:refused, why} -> fail(frame, why)
        {:error, why} -> fail(frame, inspect(why))
        result -> ok(frame, %{"result" => format(result)})   # "moved" | "level" | "rebased:N"
      end
    else
      {:error, why} -> fail(frame, to_string(why))
    end
  end
end
```
Tests: (a) tool listed; (b) an unseated/other-lead caller is refused (`"only its lead"`, copy the push_branch assertion at ~L488);
(c) a seat on a thread whose worktree is behind origin/main calls it → not `isError`, text names the result, checkout moved;
(d) dirty worktree → `isError` and text =~ "uncommitted". Reuse the repo/origin setup from Task 2 via the existing helpers in server_test.
Verify: `menard run test --in server test/server/mcp/server_test.exs`. Commit: `catch_up_branch: the service moves a seat's thread branch onto origin/main (#463)`.

## Task 4 — tell the seat it exists, docs
Files: `server/lib/server/profiles.ex` (the brief near L397 / the coworker rules: one sentence — "your sandbox can't rebase:
call `catch_up_branch`, then `push_branch`"), `adapters/claude-code/lib/citizen.ts` L129 area if a denied `git rebase`/`reset`
has a hint (add "or catch_up_branch" to the deny reason of a rebase onto main — only if such a gate exists; otherwise skip, YAGNI),
`server/AGENTS.md` / `docs/` tool list if it enumerates tools (`rg -n push_branch server/AGENTS.md server/docs`; add the sibling line).
Verify: `~/projects/menard/bin/menard run check --in server` ok (a coworker seat never runs `mise run check`; verify gates the rest).
Commit: `brief + docs name catch_up_branch (#463)`.

## Done
`menard run check --in server` ok on the branch; the eight Task 1 cases + three Task 2 notices + four Task 3 calls green;
`git log` shows four commits. Then `advance_stage`.
