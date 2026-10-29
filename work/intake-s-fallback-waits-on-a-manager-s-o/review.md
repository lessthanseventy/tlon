# Review: intake's fallback waits on a manager's open triage (#521)

**Verdict: request_changes**

Read: commit 10317b0ce67dc1488ad27df85776ba185f804a6d, the one commit over c1645d1 (`server/lib/server/intake.ex`, `server/test/server/intake_test.exs`, `pr.md`). Spec/plan: tertius's brief on the thread (msg #16885).

## 1. Blocking: a consult ask never resolves in production, so one consult naming #N parks the ticket forever

`in_triage?/3` returns true while any consult ask (`consult_id` set, `mirrored == false`) naming `#N` has `resolved_at` nil:

```elixir
if Enum.any?(consults, &is_nil(&1.resolved_at)) do
  true
```

Nothing writes `resolved_at` on a consult ask. `Server.Consult.create_ask` posts a kind "chat" message and stamps only `consult_id`; the only writer of `resolved_at` is `Server.Message` line 75, reached through `Server.Attention.resolve`, which handles kind "prompt" (operator asks, stalls) only. The branch's test "an open consult naming it blocks the fallback; once resolved and 30 minutes pass it fires" reaches the resolved state with `Repo.update_all … set: [resolved_at: …]`, a state no runtime path produces.

Net effect: one `consult_peer` naming the ticket turns #521's "staffed twice" into "never staffed", silently (the fallback skips the ticket, the sheriff is never told). The plan's "open consult (consult true, resolved_at nil)" rests on a premise the schema does not hold; flagged to hronir on the thread (msg #16918).

Fix I recommend (small, keeps the plan's intent that a consult naming #N defers): treat a consult ask as a deferral stamp like a manager reply, not a gate, and bound it to after the route:

```diff
       from(m in Server.Message,
-        where: not is_nil(m.consult_id) and m.mirrored == false and ilike(m.body, ^"%##{ticket.id}%"),
+        where:
+          not is_nil(m.consult_id) and m.mirrored == false and m.created_at > ^ticket.updated_at and
+            ilike(m.body, ^"%##{ticket.id}%"),
         order_by: [desc: m.id]
...
-    if Enum.any?(consults, &is_nil(&1.resolved_at)) do
-      true
-    else
-      stamps = Enum.map(consults, & &1.resolved_at) ++ Enum.map(replies, & &1.created_at)
-      newest = Enum.max([ticket.updated_at | stamps], DateTime)
-      DateTime.diff(now, newest) < after_s
-    end
+    stamps = Enum.map(consults ++ replies, & &1.created_at)
+    newest = Enum.max([ticket.updated_at | stamps], DateTime)
+    DateTime.diff(now, newest) < after_s
```

and the consult test becomes: a consult 10 minutes old defers; one 40 minutes old does not. Update the moduledoc sentence and `pr.md` to match (no "open consult blocks"). If the tech lead wants "blocked until answered", the object that is resolved at runtime is the manager's open operator ask on the root thread (`kind == "prompt"`, `payload["ask"]`), not the consult; that is his call, not a reason to keep the current branch.

## What holds

- (a)(1): a manager message on the root thread after the route naming `#N` defers 30 minutes from that message. Correct; the `~r/##{id}(?!\d)/` guard is tested against `#N0`.
- (b): the fallback posts on the root thread naming the new thread. Correct and tested.
- `held` path untouched; the two pre-existing stalled tests still pass.
- Verify: `menard run check --in server` 2407 tests, 0 failures; `mise run check` green. bench_contrast unmeasurable (the branch edits no steering), not a finding.