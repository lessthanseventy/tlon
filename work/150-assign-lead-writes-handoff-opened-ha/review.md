verdict: request_changes

#150 — assign writes `handoff_opened`; `handoffFrom` reads it from the feed.

The change is correct and tested. `Server.Staff.assign/2` writes one `handoff_opened` event (`from`/`to` lead names) only when a thread's lead actually changes; a first staffing and a same-lead re-seat write none (guarded `when not is_nil(old) and old.id != agent.id`). `Server.Office.Room.activity/2` sets that row's `who` to the old lead via `event_who/1`, and `handoffFrom` (office/kit/plane.ts) reads the newest `handoff_opened` for the thread within 60s off the activity feed instead of `visits`. The live-uqbar gate is gone, as the ticket intends. Tests went red first on both sides — `staff_test.exs` (event-on-change, none-on-first, none-on-re-seat), `office/room_test.exs` (the `who` field, on a non-empty thread), `plane.test.ts` (newest/stale/other-thread/wrong-kind/empty) — and `menard run check --in server` is green (1973, 0 failures).

## Blocking

**`office/AGENTS.md:33` is now stale.** It still reads `handoffFrom` off `visits`; `handoffFrom` now reads the activity feed (`plane.ts`), not `visits`. The root AGENTS.md is explicit that a change making a module's AGENTS.md stale updates it in the same commit — stale guidance is worse than none because a weaker model trusts it. One-line fix: in that clause, `handoffFrom` off `visits` → `handoffFrom` off the activity feed. (`a.visits` itself stays — `sim.ts:851` still uses it for the lounge visiting map, so only this clause is wrong, not the field.)

## Non-blocking (follow-up)

`Staff.assign/2` records the event inside a `tap` whose return value the caller never sees, so an `{:error, _}` from `record_event` is swallowed silently — a lead change could commit with no handoff row and the post would not fly. `record_event` is a plain insert that essentially cannot fail barring a DB outage, and adding error handling would be speculative complexity for a non-case, so this is a note, not a fix-now.