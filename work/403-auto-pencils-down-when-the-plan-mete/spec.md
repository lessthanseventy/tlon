# Auto pencils down when a plan meter nears its cap (#403)

## Goal
When a Claude plan window (5-hour or weekly) reaches the operator's threshold, the office goes to
pencils down by itself and says why on the root thread, so the last of a bucket isn't spent on new work.

## Design
1. **Trigger**: on the report path (`Server.Usage.report/1`, fed by `POST /api/usage/claude`), after a
   successful merge, compare each reported window's `percent` to the knob. Readings are pushed; no polling.
2. **Knob**: `auto_pause_at` in `Server.OperatorConfig` `@knobs`, percent, default 90, nullable (nil = off).
   Applies per window; whichever crosses first fires.
3. **Action**: only when `Server.Pause.state() == :working`: `Server.Pause.pencils_down/0`, then one post on
   the root thread: `"5h at 91%, resets 14:00 — pencils down, back to work when you say"`
   (`weekly` for seven_day; reset time from `resets_at`, omitted if nil).
   A manual pencils down or lights out is never touched and never re-announced.
4. **Override sticks**: latch the `{window, resets_at}` the pause fired on (persisted in the operator
   settings file as `auto_paused_for`, so a restart doesn't re-fire). Never fire again for that same pair;
   a new `resets_at` (next window) is a new pair.
5. **No auto-resume** in v1; the operator says `back_to_work`. Auto-resume at `resets_at` needs a timer: a
   follow-up ticket.

## Known limit
The meter is in memory: nil after a restart until the first plan turn reports, and only as fresh as the
last turn. So this never escalates past pencils down.

## Out of scope
Auto-resume, lights out, per-window thresholds, #404/#405.

## Done when (tests, `menard run test --in server`)
- A report crossing the threshold while `:working` pauses the office and posts the reason on the root thread.
- A report after `back_to_work` on the same `{window, resets_at}` does not pause again; a new `resets_at` does.
- A manual pencils down / lights out is left as is (no state change, no post).
- Below threshold, knob nil, or an invalid report: nothing happens.
- Docs in sync: the `Server.Usage` moduledoc and the settings doc name the knob.
