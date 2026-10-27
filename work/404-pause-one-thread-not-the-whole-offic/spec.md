# #404 — pause one thread, not the whole office

Source: ticket #404 (refiled from #172 item 7): "pause a single thread — its lead wraps up, nothing
new is delivered to it, resume picks it back up — without stopping the rest of the office".
Build after #384 (#403, automatic pause) is on main: same file (`pause.ex`, `switchboard.ex`),
different functions.

## Requirements

1. The operator can pause one thread and resume it. Other threads are unaffected.
2. Pausing tells that thread's lead (a `notice`, wakes nobody) to finish the turn, commit and stop.
3. While a thread is paused, nothing is delivered to it except the operator's own posts, which
   still wake its lead (same rule as the office-wide pause).
4. A paused thread is not nudged to continue and is not a `stalled` Need; the wake-not-taken
   alert skips it.
5. Staffing a new child of a paused thread is refused. Existing children are NOT paused: a pause
   is a lever on one lead, its running children finish under their own leads (operator, 2026-10-27).
6. Resume clears the mark, drains what was held, and posts "@lead back to work" on that thread.
7. Intake is untouched. Lights out stays office-only.

## Design

- **Mark:** nullable `paused_at :utc_datetime` on `thread` (migration; hits the limit gate, so
  the operator approves it). No new `state` value: a paused thread stays `"open"` to every query.
- **API:** `Server.Pause.pause_thread(id)` / `resume_thread(id)` -> `{:ok, thread}` /
  `{:error, :not_found | :not_open}`; `Pause.thread_paused?(id)`. Idempotent: pausing a paused
  thread says nothing again.
- **Split** `tell_live_threads/0` and `wake_stopped_threads/0` so each takes one thread id; the
  office-wide versions loop over them. Resume wakes the lead only if the thread was paused
  (`paused_at` set), so a thread stopped by office pause is woken by office back-to-work, not twice.
- **Delivery:** `Switchboard.paused_for?/1` becomes `paused_for?/1` = office paused OR
  `thread_paused?(message.thread_id)`, in both `deliver/1` and `claim_reached/2`; operator
  authors are exempt as now. The existing drain re-delivers on resume (`resume_thread` calls it).
- **Excused checks** (model: `Server.Blocked`): `Workline.Continuation` (next to `Blocked.blocked?`),
  `Office.Needs` stalled and wake-not-taken (next to `Blocked.thread_ids()`).
- **Staffing:** `Tickets.start_thread/2` / `staff_child` refuse when the parent thread is paused
  (`{:error, "thread N is paused: resume it first"}`).
- **Route:** `POST /api/threads/:id/pause` and `/resume` in `operator_api.ex`, returning
  `{thread_id, paused}`; documented in its moduledoc.
- **Office-wide interplay (operator, 2026-10-27):** office back-to-work does not clear a
  per-thread pause (a separate, deliberate choice); the thread stays paused until resumed itself.

## Out of scope

TUI key (junior follow-up ticket), pausing children, lights out per thread, any change to `held`
(intake-only label).

## Tasks (TDD, each its own commit)

1. Migration + `Thread.paused_at` + `Pause.pause_thread/resume_thread/thread_paused?` with tests
   (mark set/cleared, idempotent, notice posted, resume posts "@lead back to work").
2. Switchboard hold: test a paused thread's lead gets no wake from a coworker post, the operator's
   post still wakes, another thread unaffected, resume drains the held message.
3. Excuse Continuation, stalled Need, wake-not-taken for a paused thread (test each).
4. Refuse staffing a child of a paused thread (test).
5. operator_api routes + moduledoc (test through the route).

Verify: `mise run check`.

## Done when

Tests show: a paused thread gets no delivery, Continuation or stalled nudge while other threads go
on; an operator post still wakes its lead; resume delivers what was held and wakes the lead.
