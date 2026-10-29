# Review — play-menu-e-opens-the-toys-as-a-numbered (#607), round 2

**Verdict: APPROVE** — reviewed a624f83113325eb75e2b75f927d007a0fbb305f8 against origin/main, and the delta since my round-1 verdict (96ec321).

## Round-1 findings, checked

1. **FIXED — a toy fired from the play card lost the card.** `Mode` is now `{ kind: "play"; from?: Mode }` (office/tui/main.ts:76) and `open()` adds `from` for play as it does for person/thread/look/review/issue (main.ts:635). The row's `run` calls `back()` first, which restores `mode.from`, then `playDo` reads `mode`: `under` is the person again, and the `mode.kind === "pet"` branch on `play.pet` is reachable. New test in office/test/navigation.test.ts: crew → person → `E 8` → "pat pat" with the person's card still on screen and no HOME header. Verify ran it green on this head.
2. **FIXED — office/AGENTS.md wording.** Line 21 now says "the play card's fire drill row (`play("drill")`)" and "row 1 of the sandbox's play card plays one". No reference to the retired F or to `e`.
3. **FIXED — every play row has a `playDo` case.** office/test/sandbox.test.ts slices the `playDo` body and asserts `case "${b.id}"` for each `PLAY_ROWS` entry, guarded by a non-empty check.

## Also on the branch (out of scope for #607, read anyway)

office/test/rack-card.test.ts: per-wait deadline (e16c9e1), waits for the full "THE RACK · all green" header (bdac7f1), restarts tmux via `killServer(socket)` (a624f83). All three read correct; afterAll keeps a bare kill-server, which is fine for teardown.

## Spec compliance

- One `sandbox-play` binding left (`play.e`, key E); D/T/F/N/W/P/C are gone from keys.ts. keys.test narrows to one key.
- `card:play` has nine numbered rows 1–9 (event, Gary, doorbell, drill, treat, night, weather, pet, call); night/weather/call are filtered when there is no `world`.
- Gary's direct summon is row 2 (`play.gary`).
- No new key convention: digits are already a card's numbered menu.

## Not findings

- bench_contrast rows read "unmeasurable: office/AGENTS.md — a seat reads it, the bench never loads it". Not a REGRESSION; no habit proposed.
- Verify's `mise run check` passed on a624f83 (office: 940 pass, 0 fail). That is the server's run; I did not run the gate or the drive walk myself.

## Follow-ups (non-blocking)

See the follow_ups posted with this verdict: the navigation test's bare kill-server on a reused socket, and E pressed on the play card dropping `from`.
