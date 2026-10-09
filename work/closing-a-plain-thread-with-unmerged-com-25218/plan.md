# Plan — closing a plain thread with unmerged commits (ticket #81)

**Decision:** TRACK, don't refuse. Refusing leaves the agent stuck holding a thread it believes is done; tracking
(`Server.Workline.promote/1`, = `tlon-cli track`) puts the work into the stage machine at `build`, where the
merge queue lands it. `close_thread` on such a thread returns `{:tracked, thread}` and the thread stays open.
Assumption: "plain" = `stage == nil`; "unmerged" = `Server.Worktree.holds/2` non-nil (dirty OR commits not on main —
dirty work strands just as well). No worktree on disk → nothing to strand → close as today.

Gate commands (unsandboxed): `~/projects/menard/bin/menard run test --in server <file>` then `... run check --in server`.

## Task 1 — `Server.Worktree.stranded/2`
Files: `server/lib/server/worktree.ex`, `server/test/server/worktree_test.exs`.
1. Test first (in worktree_test.exs, new `describe "stranded/2"`): (a) no checkout → `nil`; (b) `ensure` a worktree, no
   commits → `nil`; (c) commit a file in the worktree (`System.cmd("git", ["-C", wt, ...])` add/commit) → string
   containing `"unmerged"`. Run → red (undefined function).
2. Add after `holds/2`:
```elixir
  @doc "Why closing the thread would strand its checkout — `holds/2`, but nil when no checkout exists."
  @spec stranded(String.t(), String.t()) :: String.t() | nil
  def stranded(repo_path, slug) do
    if File.exists?(Path.join(path(repo_path, slug), ".git")), do: holds(repo_path, slug)
  end
```
3. Green. Commit: `fix: Worktree.stranded/2 — would a close strand this checkout?`

## Task 2 — `Channel.close_thread` tracks instead of stranding
Files: `server/lib/server/channel.ex`, `server/test/server/channel_test.exs` (or workline_test.exs if it already
builds a repo-backed thread — copy its project/repo setup; `Server.repo_for_thread/1` must resolve).
1. Test first: plain thread (stage nil) in a project whose repo is a temp git repo; `Worktree.ensure(repo, "t#{id}")`,
   commit in it; `assert {:tracked, t} = Channel.close_thread(thread)`; assert `t.stage == "build"`, `t.state == "open"`,
   worktree path still exists under the new slug (`Worktree.names(repo)` includes `t.slug`), and a message from
   `"tlon"` in the thread mentions "unmerged". Second test: same thread with NO commits → `{:ok, closed}`, state "closed".
   Third: thread with `stage` set is untouched by the guard (workline finish path still returns `{:ok, _}`).
2. Implement — in `close_thread/1` add a first clause that guards on `stage: nil`:
```elixir
  def close_thread(%Thread{stage: nil} = thread) do
    case stranded_reason(thread) do
      nil -> do_close(thread)
      reason -> track_instead(thread, reason)
    end
  end
  def close_thread(%Thread{} = thread), do: do_close(thread)
```
   Rename the existing body to `defp do_close/1` (unchanged). Add:
```elixir
  defp stranded_reason(thread) do
    with {:ok, repo} <- Server.repo_for_thread(thread),
         false <- root_machine_thread?(thread) do
      Server.Worktree.stranded(repo, Server.Worktree.name_for(thread))
    else
      _ -> nil
    end
  end

  # Closing would orphan the branch: track it (same as `tlon-cli track`) so the merge queue lands it.
  defp track_instead(thread, reason) do
    with {:ok, tracked} <- Server.Workline.promote(thread) do
      mention = if lead = thread_lead(thread.id), do: "@#{lead} ", else: ""
      post(%{thread_id: thread.id, author: "tlon",
             body: "#{mention}⚠ not closed: #{reason}. Tracked as workline #{tracked.slug} at build — finish it and let it merge."})
      {:tracked, tracked}
    end
  end
```
   Update `@doc` of `close_thread` to state the tracked return. (promote's `rename_worktree` moves `t<id>` → slug.)
3. Callers (each must handle `{:tracked, t}`):
   - `server/lib/server/mcp/tools/coordination.ex:195` (`close_thread` tool): replace `{:ok, closed} = ...` with a `case`;
     `{:tracked, t}` → `ok(frame, %{"stays_open" => true, "tracked" => t.slug, "why" => "unmerged commits — tracked as a workline instead of closed"})`.
   - `server/lib/server/mcp/tools/thread.ex:329` (`finish`): add `{:tracked, t}` to the `else` → same `stays_open` reply.
   - `server/lib/server/mcp/operator_api.ex:293`: `reply/4` has no `{:tracked,_}` clause — map it with
     `case Channel.close_thread(t) do {:tracked, x} -> reply(conn, {:ok, x}, &thread_row/1); r -> reply(conn, r, &thread_row/1) end`
     (row shows stage build/state open, which is the truth). Update the route doc line 47.
   - `workline.ex:1134` is stage-set (merged) → never hits the guard; leave.
   Add a tool-level test next to existing close_thread tests in `test/server/mcp/server_test.exs` asserting `stays_open`.
4. Green on channel/workline/server_test files; then full `run check --in server`. Commit: `fix: closing a plain thread with unmerged commits tracks it instead of stranding the worktree`.

## Task 3 — manager triage brief
Files: `server/lib/server/profiles.ex` (~line 428, the TICKET bullet), `server/test/server/profiles_test.exs`.
1. Test first: the manager brief text contains `"changes code gets a workline"` (follow how profiles_test already
   asserts on the manager prompt). Red.
2. Add one sentence to the TICKET bullet: `A ticket that changes code gets a workline (stage build+), never a plain thread — a plain thread's branch is stranded when it closes.`
3. Green. Commit: `docs: manager triage — a ticket that changes code gets a workline`.

## Task 4 — docs sync (same PR)
`server/AGENTS.md` / `server/docs/spec.md`: if either describes `close_thread` semantics, add the tracked outcome
(`grep -n close_thread server/AGENTS.md server/docs/spec.md`). Commit with Task 2 if touched. Final: `mise run check`.

**Done =** all three tests green, `mise run check` green, and the Task 2 test proves a plain thread with unmerged
commits is never closed with a stranded `t<id>` worktree (it becomes a build workline, lead @mentioned).
