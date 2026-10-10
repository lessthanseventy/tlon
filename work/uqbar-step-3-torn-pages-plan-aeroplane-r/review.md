VERDICT: approve — workline A (the aeroplane).

Re-review of the one change since cfa395f (ae096aa, "lands at the lead's desk, not where the lead stood at launch"): `fly()` now targets `plan.home(layout(a), lead)` — the lead's fixed desk spot — instead of the live actor's `x/y` at launch. 2 lines in `wide.ts` + one focused test.

Checked:
- `plan.home(l, agent): Spot | null` (kit/sim.ts:68) returns null when the lead has no desk, so the fallback chain desk → card → boardEdge is preserved exactly. The only behaviour change is desk-vs-live-position, which is the derived decision (#1152): the lead can be teleported between launch and landing.
- The new test teleports the lead off-desk (x+90, y+60) before `fly()`, asserts the plane's last glide tick lands at `{desk.x, desk.y-10}`. Under the old code `who` still resolves to the teleported actor → red; under the fix → green. Genuine RED→GREEN.
- Hand-off `via` waypoint still uses the old lead's live position — correct, it's a transient pass-over, not a landing. Argos midpoint derived from the new `to`; no leftover `who` reference.
- Verify gate: `mise run check` green on the branch (exit 0, 9 passed). I did not rerun the suite; that is the server's verify record.

This resolves the plan's "Open" item #2 (plane lands where the lead walks, not the desk) — it now lands at the desk.

Follow-ups (non-blocking, still open):
- True lead reassignment leaves no server record: `assign_lead` writes nothing, `handoff_opened` is unwritten. A's hand-off rides `visits` only while a uqbar session is live. File its own ticket (plan decision 5) — `assign_lead` writes a `handoff_opened` event with old/new lead, then `handoffFrom` reads that.
- The aeroplane is unverified live: no `office:drive` run with a seeded feed row. Unit tests + golden cover the sim; live behaviour is stub-driven only.