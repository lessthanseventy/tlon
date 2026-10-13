# Review — after-a-machine-restart-a-coworker-handl (5c3df82)

**Verdict: request_changes** — one blocking finding, one-line fix plus a test. The rest is sound.

## Blocking: an ended row with no successor is fenced as "superseded"

`take_wakes` compares the caller's `session_id` with `identity.session_id`, which `Server.MCP.Tokens.resolve/1` fills from `Staff.live_session/2` at read time. When the live row has been ended and nothing has registered since, that is `nil`, and `claimed != nil` is true: the only real pane is answered `{superseded, by: nil}`, submits "a newer session now holds your seat, stop" as a turn, and sets `superseded = true`, so it never polls or registers again.

Ordinary paths reach it:
- `finish` → `Channel.do_close` → `Staff.end_thread_sessions` while the pane is up. Its window lives until `sweep_orphans` runs; every poll in between is fenced. If the operator's reply reopens the thread first, the window exists, so `Arbiter.Tmux.spawn` sees it running and spawns nothing: the wake waits for the cold sweep.
- `Staffing.clear_context` ends the rows, then kills the windows; polls between the two are fenced (harmless, but the submitted text is false).

Before this change a pane with an ended row kept taking wakes (`Wake.take` is keyed by thread+agent); this makes it stop for good.

Fix: fence only when a *different* live session exists.

```diff
--- a/server/lib/server/mcp/tools/wakes.ex
+++ b/server/lib/server/mcp/tools/wakes.ex
@@
     case params[:session_id] do
-      claimed when is_integer(claimed) and claimed != identity.session_id ->
+      claimed when is_integer(claimed) and is_integer(identity.session_id) and claimed != identity.session_id ->
```

Test (server_test.exs, beside the new one): register, end the session row (`Staff.end_session`), queue a wake, `take_wakes` with the old id → the wake is returned, not `superseded`.

Known trade: a twin whose respawn has since ended (pane gone, nothing re-registered) can take wakes again. That is the pre-change behaviour, and #262's `Server.Orphans.retire` (now on main) signals that process before the next spawn anyway.

## Verified
- Read the full diff; the server test exercises the real case (twin and respawn registered on one token, twin fenced with `by: live_id`, wake kept for the live one).
- `register` supersedes the prior live row (`Staff.supersede_live`), so `identity.session_id` is the respawn's id for the twin's call — the fence does what it claims when a successor exists.
- Verify stage recorded `mise run check` exit 0 on the branch.
- Branch base is origin/main's tip at the time; #262 landed since and touches no shared file (orphans.ex, arbiter/tmux.ex vs wakes.ex, mod.ts).

## Non-blocking (follow-ups)
- `mod.ts` `session.start` resets `registration`, `registerFailed`, `superseded` but not `sessionId`; a register that fails on a second start leaves the previous id in play.
- The `by` field is `nil` when no live row exists; after the guard above the field is always an integer, so the moduledoc's `"by": id` holds.
