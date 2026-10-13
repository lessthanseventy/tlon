# Review — toy step 4: the front door and the doorbell (round 2)

**Verdict: approve.** All three blockers from the first round (7391165) are fixed on the branch, test-first where a seam existed, and the three nits were taken on the same pass. Re-read `git diff 7391165..HEAD -- . ':!work/'`; ran `bun test` on data/door/door-draw/door-visit (19 pass, 0 fail) and `tsc --noEmit` (clean).

## Blockers from round 1 — fixed

1. **`status()` drops `release`** — `office/tui/data.ts` now copies `release: j.release` (undefined for an older server, as the type says). `data.test.ts` serves `release: {sha, cut_at}` and asserts it comes back on the snapshot; emma reported it RED before the fix (#6417).
2. **Restart gap skips `tellNews`** — `tui/main.ts` keeps `lastOk`/`lastOkNeeds` and diffs against the last **ok** snapshot, not the previous poll; `before`/`beforeNeeds` are gone from `refresh()` (no dangling reference). Side effect is as called out: needs and a health warn that landed during an outage are told once it's back. No unit seam in main.ts — verified by reading, as emma said.
3. **`office/AGENTS.md`** — the wide-room paragraph now names the door, `kit/door.ts`, `arrivals`, the pizza/carrier/cookies/tourist visitors, and that the visitor is sim state.

## Nits — taken

- `floor.ts` door comment now states the real geometry (one pixel from the muster grid's `w-17` column, fire outranks the door).
- door-visit "rail room" test renamed to what it tests.
- The vacuous `>= 0` assertion is gone; the test pins `nextRing > tick` after 100 steps.

## Unchanged and still fine

Sim, draw, server `live_release/0`, `Office.status`, golden re-hash — as in round 1.
