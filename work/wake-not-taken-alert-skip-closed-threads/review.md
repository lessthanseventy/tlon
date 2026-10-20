# review: wake-not-taken-alert-skip-closed-threads

**verdict: approve**

Meets all three of #479's goals, with a test per goal and a green gate (`menard run check --in
server`: 1926/0; `mise run check`: exit 0, both recorded).

## what it does

1. **closed threads skipped** — `Channel.do_close/1` calls `Server.Wake.clear/1` in teardown order
   (after `end_thread_sessions`, before `Tickets.done_for`), dropping the thread's pending wakes.
   `report_overdue/0` re-checks `thread.state == "open"` before paging, so a wake queued against an
   already-closed thread — or one closed between the delete and the check — is let go unreported.
   `clear` is the only new caller.

2. **seats that answered skipped** — `took_it?/1` counts a wake as taken if its agent posted on ANY
   thread since the wake was queued (`m.created_at >= w.inserted_at`). Cross-thread is deliberate and
   matches the docstring: a seat that answered from its lobby heard it. A post from before the wake
   was queued does not count (time-bound by `inserted_at`).

3. **one page per stall** — `paged_and_silent?/2` finds the sheriff's last page for this
   `{thread, agent}` on the workspace's beat and skips re-paging while the seat stays silent since;
   a post anywhere after the page breaks the silence, so the next overdue wake pages again. The LIKE
   `🚨 #<id> %: <agent>'s pane has not taken its wake%` matches `Sheriff.report`'s body
   (`🚨 #<id> <title>: <what>`) regardless of title, scoped by thread id and the workspace's beat.
   A `workspace_id: nil` thread falls through to `false` (no beat to dedupe against) — moot in
   practice, since `Sheriff.report` returns `:no_sheriff` for nil workspaces and posts nothing.

## verification

- `menard run check --in server` → ok, 1926 tests, 0 failed (recorded at 19:41).
- `mise run check` → exit 0 (recorded at 19:53).
- `Server.WakeTest` adds five tests: clear-on-close, closed-thread-not-reported,
  cross-thread-took-it, post-before-queue-doesn't-count, and the once-per-stall / again-after-drain
  cycle. The last traces the dedup state machine end to end (page → second wake stays at one page →
  drain → third wake re-pages to two).

## notes (non-blocking, none filed)

- `report_overdue/0` now returns `length(reported)` instead of the delete count; the sole caller
  (`Server.Jobs.Drain`) binds it to `_`, so no consumer reads it.
- `took_it?/1` and `paged_and_silent?/2` add 2–3 queries per overdue wake. The drain runs once a
  minute over a small set — not a hot path.
- The dedup LIKE interpolates the agent handle unescaped; a handle containing `%` or `_` (none do
  today) could over-match. Theoretical only — not worth a ticket.