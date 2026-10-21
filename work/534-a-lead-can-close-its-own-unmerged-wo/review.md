# verdict: request_changes

One blocking bug: `finish` with a blank `abandoned`/`superseded_by` on an unmerged workline raises `FunctionClauseError`.

## the crash

`why_closed/1` guards on `is_binary(ref)` — `""` is binary, so `%{abandoned: ""}` yields `{:abandoned, ""}` (and likewise `superseded_by: ""`). `Channel.close_as/2` trims the text, finds it blank, and returns `{:error, :why_closed}`. That atom flows back through `close/2` into the `with`'s `else`, which has no `{:error, :why_closed} ->` clause, so it hits the catch-all:

    other -> reply(frame, other, & &1)

`Server.MCP.Tool.reply/3` (tool.ex:115-117) only words `{:ok, _}`, `{:error, %Ecto.Changeset{}}` and `{:error, reason}` when `is_binary(reason)` — `{:error, :why_closed}` matches none, so it raises. The sibling `close_thread` tool handles `:why_closed` explicitly (coordination.ex:299-303); `Finish` doesn't.

Reachable: `superseded_by`/`abandoned` are optional with no trim/length validation, and an agent that sends an empty or whitespace-only string for either stands the workline down into a crash instead of the stays-open guidance that `:workline ->` gives. RED: `finish` with `abandoned: ""` on a build-stage workline raises.

## fix — one else-branch, mirrors close_thread

```diff
--- a/server/lib/server/mcp/tools/thread.ex
+++ b/server/lib/server/mcp/tools/thread.ex
@@ -447,6 +447,12 @@
       nil ->
         fail(frame, "this connection's thread is gone")
 
+      {:error, :why_closed} ->
+        fail(
+          frame,
+          "this workline hasn't merged: say why it closes — superseded_by: the PR or commit that already shipped its work (its ticket is done), or abandoned: why it is dropped (its ticket goes back to the backlog)"
+        )
+
       other ->
         reply(frame, other, & &1)
```

Add a RED test alongside the two new cases: `finish` with `abandoned: ""` (or whitespace) on a build-stage workline → no crash, stays open or a clean `isError` with the message.

## non-blocking notes

- `stage: "merged", state: "open"` workline + a why: `close_as`'s guard (`stage not in [nil, "merged"]`) treats a merged-stage thread as "any other thread", closing it normally and skipping `close_unmerged`'s ticket handling. Pre-existing `close_as` semantics, shared with `close_thread` — not introduced here, and merged work closing normally is right. No ticket.
- #80 (abandon doesn't clear the ticket's `promoted` link, so `promoted_thread_id` stays set) is already tracked and was explicitly out of scope per pr.md. Left open there.