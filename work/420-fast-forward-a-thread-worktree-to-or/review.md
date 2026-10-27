# Review — workline 420-fast-forward-a-thread-worktree-to-or @ ae4bc6a

**Verdict: request_changes.** One blocking finding, in the facade's reporting, not in `catch_up/1`. The git logic matches the spec (branch + clean + ancestor → `merge --ff-only`; detached skipped; no fetch; ancestry not patch-identity). Six tests, RED first per the builder; verify's `mise run check` passed (exit 0, 13:40:35Z). No bench_contrast row in CHECKS.

## 1. Blocking — the "checkout left where it is" post wakes or spawns the thread's lead

`server/lib/server.ex`, `say_once/4`:

```elixir
do: Server.Channel.post(%{thread_id: thread.id, author: "tlon", body: body})
```

No `kind`, so it is `"chat"` (`Message` default). `Server.Switchboard.addressed/1` on a post with no @mention and no reply falls back to `lead_name/1` → the thread's lead. A warm lead is woken (a paid turn); a cold one is spawned by `maybe_spawn_absent/1` (`agent.id == thread.agent_id`). The other server status lines (`pause.ex`, `orphans.ex`, `blocked.ex`) post `kind: "notice"` for this reason.

It bites because `Server.worktree_for_thread/1` is not only the wake path. Callers: `mcp/spawn.ex:172` (wake), `source/tools.ex:70` (every outline/edit tool call), `mcp/tools/run_task.ex:36`, `jobs/verify.ex:27`, `jobs/land.ex:162`, `verify_train.ex:75`, `mcp/operator_api.ex:686`. On a workline every builder commit is a new tip, so the next tool call posts the line and queues the builder an extra turn; at verify and at land the tip is new again and the lead is cold, so a pane is spawned to read a status line.

## 2. Blocking (same lines) — the ahead line fires when the branch is not behind main

`tell_catch_up({:ahead, n}, …)` speaks whenever the branch has own commits, including when its merge-base is origin/main itself — a workline's normal state after every commit. The comment says the line exists "so the thread knows why its checkout is behind main". Speak only when `git rev-list --count HEAD..origin/main` is non-zero.

### Patch (both)

```diff
--- a/server/lib/server.ex
+++ b/server/lib/server.ex
@@
-  # What a wake's catch-up left to say: a checkout it could not move, once per state (a lobby wakes
-  # often), so the thread knows why its checkout is behind main.
+  # What a wake's catch-up left to say: a checkout it could not move, once per state (a lobby wakes
+  # often), so the thread knows why its checkout is behind main. A notice: a bare chat post is
+  # addressed to the thread's lead and wakes or spawns them for a status line.
   defp tell_catch_up({:ahead, n}, wt, thread) do
     {tip, _} = System.cmd("git", ["-C", wt, "rev-parse", "HEAD"])
+    {behind, _} = System.cmd("git", ["-C", wt, "rev-list", "--count", "HEAD..origin/main"])
 
-    say_once(
-      wt,
-      thread,
-      "ahead:#{String.trim(tip)}:#{n}",
-      "checkout left where it is: #{n} commit#{if n == 1, do: "", else: "s"} of its own beyond origin/main"
-    )
+    # own commits on top of main are a workline's normal state: only a main that moved on is news
+    if String.trim(behind) == "0",
+      do: :ok,
+      else:
+        say_once(
+          wt,
+          thread,
+          "ahead:#{String.trim(tip)}:#{n}",
+          "checkout left where it is: #{n} commit#{if n == 1, do: "", else: "s"} of its own beyond origin/main"
+        )
   end
@@
   defp say_once(wt, thread, key, body) do
     if Server.Worktree.report_once?(wt, key),
-      do: Server.Channel.post(%{thread_id: thread.id, author: "tlon", body: body})
+      do: Server.Channel.post(%{thread_id: thread.id, author: "tlon", kind: "notice", body: body})
 
     :ok
   end
--- a/server/test/server/worktree_test.exs
+++ b/server/test/server/worktree_test.exs
@@ (test "a wake fast-forwards a checkout …")
       File.write!(Path.join(wt, "MINE"), "mine\n")
       {_, 0} = System.cmd("git", ["-C", wt, "add", "MINE"])
       {_, 0} = System.cmd("git", ["-C", wt, "commit", "-qm", "mine"])
+      # own commits on top of main: nothing to explain
+      assert {:ok, ^wt} = Server.worktree_for_thread(thread)
+      assert [] = Enum.filter(Server.Channel.thread_messages(thread), &(&1.body =~ "1 commit"))
+
+      File.write!(Path.join(repo, "NEW2"), "more\n")
+      {_, 0} = git.(["add", "NEW2"])
+      {_, 0} = git.(["commit", "-qm", "main moves again"])
+      {_, 0} = git.(["push", "-q", "origin", "main"])
+      {_, 0} = git.(["fetch", "-q", "origin"])
       assert {:ok, ^wt} = Server.worktree_for_thread(thread)
       assert {:ok, ^wt} = Server.worktree_for_thread(thread)
 
       told = Enum.filter(Server.Channel.thread_messages(thread), &(&1.body =~ "1 commit"))
-      assert length(told) == 1
+      assert [%{kind: "notice"}] = told
```

The `catch_up/1` describe block needs no change: `{:ahead, 1}` stays the return.

## 3. Design note for the tech lead (not blocking)

The spec's premise — "at wake no pane of the thread is running yet, so the move lands under nobody" — does not hold where the hook sits: the facade fires from the seven callers above, so the ff can land mid-turn under a running pane. It only moves a clean branch with no own commits to a superset of its history, and a detached (verify-frozen) checkout is skipped, so I judge it acceptable; for t1 it is the point. Wake-only would mean moving the hook into `spawn.ex`'s `cwd_export`, a plan change. Posted to @hronir on the thread.

## Checked, not findings

- `forward/1` compares `rev-parse HEAD` to `rev-parse origin/main` with both newlines intact; equal → `:level`, else `--ff-only` under an already-proven ancestor, so it cannot fail except on a lock.
- `dirty?` uses `status --porcelain`, so an unignored untracked file holds a checkout back as `:dirty` — the spec's rule, and the server is not sandboxed, so no phantom dotfiles.
- `tlon-reported` keyed on `tip:n` is the spec's "once per tip".
- pr.md names the deviation (facade, not `ensure/2`) and how it was checked.
