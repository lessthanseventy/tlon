REQUEST CHANGES — one real bug, rest is sound.

Verified: `bun test test/scharlach.test.ts test/seat-voices.test.ts` → 13 pass; `tsc --noEmit` reported nothing. Did not drive the TUI.

## Blocking

**A red never "clears" in the TUI, so a re-red won't re-tick** (`office/tui/main.ts`, `tickLedger`).
`tickLedger` returns early when `all.triage[sws] <= 0` (or `data.triage` is null). `tickForRedThreads` only forgets a thread's `ticked` entry when it is absent from the next `redIds` — but that call is skipped exactly when the board goes fully green. So: thread 7 red → ticked; build goes green (early return, `ledger.ticked` still holds 7); thread 7 red again → "already ticked", no demerit. The doc comment and the unit test "a red that clears then re-reds ticks again" promise the opposite; the test passes only because it calls the kit fn with an empty list, which the TUI never does on the green path.
Fix: on the green/empty path, reset instead of returning — `ledger = tickForRedThreads(ledger, [], all.threads)` (or `{ ...ledger, ticked: new Set() }`). Add a test at that seam if feasible.

## Non-blocking (follow_ups)

- Scharlach's canned "The build is red. I have recorded the demerit." fires at a game/couch regardless of build state.
- `seatLine`'s `{name}` → "you" replacement is dead (no line uses it).
- Fallback fires whenever `data.talk` returns `[]`, including server-side throttling, not only `--sandbox`; the comment overstates.
- Missing trailing newline in scharlach.ts and seat-voices.ts.