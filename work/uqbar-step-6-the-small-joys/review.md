# Review: uqbar-step-6-the-small-joys (a1633fd)

**Verdict: approve.**

Reviewed the three commits (aefc65e, 20379eb, a1633fd) against the design doc `docs/plans/2026-10-08-uqbar-design.md` §2/§3/§7 row 6 (no spec.md/plan.md on the branch: the workline started at build, so the ticket body and design doc are the spec).

## Spec compliance
- **Knocked book stays fallen until Uqbar sleeps; someone idle in the lounge straightens it.** `WideRoom.fallen` is set true whenever `a.uqbar` is absent and only cleared by a settled reader (`peopleAt("read")`, `STRAIGHTEN` ticks); `drawShelf` lays the spine flat on `fallen`, not on `live`. Matches §2.
- **Nina bats at the book when it flies low; it flinches shut.** `swatted` (reach box around the cat, flying only), gated on her not sleeping and a 200-tick quiet; `drawBook` shows the closed frame while `tick < flinch`. One voice set added. Matches §3.
- **A caught plane's post is dog-eared, 🐾, nothing else changes.** `fly` now returns whether Argos caught it; the TUI earmarks the feed row and the Reader draws 🐾 on that message's header. Matches §3.
- **Deterministic under the test seed.** No `Math.random` in any of the three; `caughtNth` is arithmetic. Matches §7's check.

## Verified
- The dog-ear key joins a feed row (`at`, `who`) to a thread message (`at`, `author`). Both are `m.created_at` / `m.author` off the same `Server.Message` struct (`server/lib/server/office/room.ex:40`, `server/lib/server/office.ex:120`), Jason-encoded the same way, so the lookup matches.
- Cat `play` is an existing `CatMode`; setting it mid-walk clears `path` so she does not keep walking after the swat.
- `bun test test/uqbar.test.ts test/dogear.test.ts`: 30 tests, 0 fail (recorded). Server verify recorded `mise run check` exit 0 on this branch.
- `office/AGENTS.md` updated in the same change.

## Non-blocking
See follow-ups: dog-ears live only in the TUI process.
