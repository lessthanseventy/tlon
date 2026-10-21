# Review — wake-overdue alert: don't page a seat whose pane is gone

**Verdict: approve.**

Closes #543. Branch `work/wake-overdue-alert-pages-a-seat-whose-pa` @ 53a306f.

## What changed

`Server.Wake.report_overdue/1`'s filter chain gains `seated?(thread, w.agent)` ahead of
`took_it?`/`paged_and_silent?`. A wake now pages the sheriff only if the addressed seat:

- holds the workline's current stage (`holds_stage?` — `true` for `stage: nil`, so unstaged
  threads keep paging when the seat is live; staged threads require `Channel.thread_lead/1 == agent`),
- has a live session on the thread (`live_session?` — a `Server.Session` with `ended_at` nil), and
- has a window for the thread (`windowed?` — reusing `Office.windowed?/3`, widened to public with a `@doc`).

Any one false and the wake is let go unpaged. The wake row is already deleted by `delete_all`
upstream, so `seated?` gates only the page — coherent with the ticket's "drop the wake, don't page."

`windowed?` reuses the office's liveness read rather than inventing a third: `Tmux.list_windows/1`
returns `:not_up` → no window (drop), a fault `{:error, _}` → can't prove absent (don't drop), else
`Office.windowed?(tabs, thread.id, agent)`. The `:not_up`/fault split is the documented office
convention and is respected.

## Spec compliance

Matches the operator's ask (#11045) and the tech lead's read (#11051): server-side filter in
`report_overdue/1`; drop, don't reroute (no second routing path — `Switchboard.redeliver_unheard/1`
and staffing handle a moved-on lead); reuse the existing liveness read; RED first. No spec was
written (tertius said so) — the PR + thread record stand in, and the change tracks them exactly.

## Tests

Four new tests in `wake_test.exs`, each isolating one branch:

- "a wake to a seat with no window never pages" — `tmux_cmd` returns `{"no server running", 1}`,
  which `@not_up` matches, so `windowed?` is false. Session and stage still hold → only the window
  branch flips. Non-vacuous (regex verified).
- "a wake to a seat whose window has no session never pages" — ends all sessions but leaves
  pierre's window from the shared `live_seat!` setup, so `windowed?` stays true and only
  `live_session?` flips. Clean isolation.
- "a wake to a seat with a session but no window never pages" — overrides `tmux_cmd` to a
  scharlach window; pierre has a live session but no window → only the window branch flips.
- "a wake to a seat that no longer holds the workline's stage never pages" — reassigns the lead
  to emma and sets `stage: "build"`; pierre keeps session + window → only `holds_stage?` flips.

Existing tests were updated to set up a live seat (`live_seat!`), since a seat with no pane no
longer pages — the intended behavior change. RED-then-GREEN claimed (4 failing before the filter);
verify gate green: 1974 tests, 0 failures.

## Non-blocking note

`windowed?` calls `Tmux.list_windows` once per overdue wake, bypassing the office's
`persistent_term` tab cache. Overdue wakes are few and deduped per `{thread, agent}`, so the cost
is negligible today; noted only so it's not a surprise if the fleet grows. Not worth a follow-up
ticket.