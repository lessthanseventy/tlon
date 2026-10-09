# Review: toy step 1 — sandbox mode

**Verdict: APPROVE.**

Verified by reading the diff `main...HEAD`. I did not re-run the gate. The verify stage recorded `mise run check` as green (exit 0).

## Spec compliance
- Matches plan decisions 1–5:
  - `data.useFake` is the single seam in `call()`.
  - GETs to `/office` are served by the toy world.
  - Writes return 409 "it's a toy".
  - `toy()` is a pure constant world.
  - Play keys are handled in `toyKey()`, only when `world` is set. They sit after the picker, input, confirm, editor and reader branches, so they never steal text input.
  - Normal mode is untouched.
- The `office:sandbox` task exists, and the task manual is regenerated.
- A test pins `PLAY` against the `case` keys in `toyKey`, so the help line cannot drift from the handler.

## Findings (non-blocking)
1. `n` calls `setClock` only on rooms already in `rooms`. A room first built after night is toggled gets the real clock for its sim. Render does use `world.now()`, so the visuals are right and only sim behaviour could lag. Fix it in a later step if it shows.
2. `RailRoom.render` ignores the new `now` argument, so night is visual in the wide room only. This is acceptable for step 1.
3. `play()` is an explicit stand-in; steps 3–5 are meant to replace its body.
4. The `fake` module state is covered by a test that resets it in `finally`.

No bugs or security concerns found: no network, no file writes, and the sandbox is opt-in via flag or env var.