# Review — workline 420-fast-forward-a-thread-worktree-to-or @ 94821b8 (round 5)

**Verdict: request_changes.** One blocking finding, and it is partly mine: the patch I posted in round 4 picked the wrong tell. 94821b8 gates the catch-up on `Keyword.get(opts, :assign, true)`. Every production spawn joins with `assign: false`, including the lead's own wake, so on this branch the feature never fires outside a hand `tlon-cli join` and the test suite. Verify's `mise run check` passed on 94821b8 (exit 0, 14:28:38Z); `menard run test` on spawn_test + worktree_test: 64 tests, 0 failed; no bench_contrast row among the CHECKS shown.

## Fixed since round 4

- Rider join: `cwd_export/3` skips the catch-up when `assign: false`; test "a rider join (assign: false) never moves the checkout under the lead's live pane" joins `codex` (lead), moves main, joins `reviewer` with `assign: false`, refutes `NEW`. Red without the guard. Good test, keep it as is.
- Outside guard pinned: test puts the repo's own main one commit behind origin/main, joins `uqbar` on the study (whose lead is uqbar: `Outside.study/1` opens it with `agent_id: uqbar`), asserts `rev-parse HEAD` unchanged. Red with the guard removed. Good.

## Blocking

1. **The wake path is `assign: false`, so the catch-up is dead in production.** The witness, every `Spawn.join` caller in `server/lib`:

```
switchboard.ex:368   Spawn.join(home.id, agent.name, assign: false)     # maybe_spawn_absent: THE wake spawn, the lead included
crew/tmux.ex:49      joiner().(thread_id, handle, mandate: "machine", assign: false)   # spawn_crew
coordination.ex:177  Spawn.join(thread.id, lead, assign: false)         # seating a child's lead
```

`maybe_spawn_absent` is the only autonomous spawn: it joins the lead onto its own thread (`spawn_home`: `agent.id == thread.agent_id -> thread`) with `assign: false` on purpose, "never the thread's lead because they were named on it", meaning it must not re-seat. #420 is "fast-forward … on wake", and on this branch wake does nothing. Nothing pinned it because every spawn test joins with the default.

The tell is lead identity, not `:assign`. `ensure/3` runs `maybe_assign` before `cwd_export`, so on a staffing join `thread.agent_id` is already the joiner; on the wake spawn it is the lead already; on a rider join (crew pane, reviewer window, coordination child) it is someone else. Patch:

```
server/lib/server/mcp/spawn.ex
-         {:ok, cwd} <- cwd_export(thread, agent, opts) do
+         {:ok, cwd} <- cwd_export(thread, agent) do
…
-  # Only a staffing join catches the checkout up: a rider (`assign: false`) joins while the lead's
-  # pane is mid-turn, and a fast-forward under it is what the catch-up must never do.
-  defp cwd_export(thread, agent, opts) do
+  # Only the thread's lead catches its checkout up. The switchboard's wake spawn joins the lead with
+  # `assign: false` (it never re-seats), so `:assign` is not the tell; a rider (a crew pane, a reviewer
+  # window) is not the lead and joins while the lead's pane is mid-turn, where a move must never land.
+  defp cwd_export(thread, agent) do
…
-        if Keyword.get(opts, :assign, true) and agent.name not in Server.Outside.names(),
+        if agent.id == thread.agent_id and agent.name not in Server.Outside.names(),
```

RED test first, in spawn_test.exs next to "a spawn brings a checkout with no work of its own up to origin/main": same setup, first `Spawn.join(thread.id, "codex")` seats codex, main moves, then `assert {:ok, _} = Spawn.join(thread.id, "codex", assign: false)` and `assert File.exists?(Path.join(wt, "NEW"))`. It fails on 94821b8. The rider test stays red-without-guard (reviewer is not the lead), and the outside test stays red-without-guard (uqbar leads the study), so both round-4 pins hold under the new gate.

## Follow-ups (not blocking)

- `say_once` keys the error path on the constant `"error"`, so a second, different failure after the first is silent until the state changes. Note only.