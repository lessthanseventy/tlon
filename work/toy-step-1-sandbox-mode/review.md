# Review: toy step 1 — sandbox mode

**Verdict: APPROVE.**

I read the `main...HEAD` diff. I did not re-run the gate. The verify stage recorded `mise run check` as green (exit 0).

## Spec compliance
- `data.useFake` is the single seam in `call()`. GETs to `/office` return the toy world, other GETs return 404, and every write returns 409 "it's a toy".
- `toy()` has no network or file access. The sandbox is opt-in through `--sandbox` or `OFFICE_SANDBOX=1`, so normal mode is unchanged.
- `toyKey()` is a no-op without `world`. It runs after the picker, input, editor and reader branches, so it can't swallow typed text.
- `office:sandbox` exists as a task and the task manual is regenerated.
- A test pins `PLAY` to the `case` keys in `toyKey`, so the help line can't drift from the handler.

## Findings (non-blocking)
1. `n` calls `setClock` only on rooms already in `rooms`. A room built after night is toggled gets the real clock for its sim behaviour. Render uses `world.now()`, so the visuals are correct.
2. `RailRoom.render` ignores the new `now` argument, so night shows only in the wide room. Acceptable for step 1.
3. `play()` is a stand-in for the scenes in steps 3–5, and its comment says so.

No bugs or security concerns found.
