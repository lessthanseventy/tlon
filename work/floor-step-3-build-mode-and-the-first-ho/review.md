## Verdict: request_changes (supersedes my earlier approve)

A grader review on this thread caught a real bug my first pass missed. I reproduced it independently with a standalone script against `office/kit/home.ts` before writing this up — it's confirmed, not speculative.

### Confirmed bug: carry + undo can duplicate a tile
`pickUp` removes a tile from `home.tiles` into `carrying` **without pushing a history entry**. If an *earlier* mutation (on some other tile) already pushed a history entry that still contains the carried tile, pressing `undo` after the pickup pops that earlier snapshot back into `home.tiles` — while `carrying` still holds the same tile. Repro:

1. `home = {living@(0,0), kitchen@(5,5)}`
2. `rotate(living)` → pushes history entry `{living, kitchen}` (kitchen still present)
3. move cursor to kitchen, `pickUp` → `home = {living'}`, `carrying = kitchen` (no history push)
4. `undo` → pops the step-2 snapshot, which still has kitchen → `home = {living, kitchen}` **and** `carrying = kitchen`

Dropping now writes a second kitchen tile into `home.json`. Standalone test run confirmed: `home.tiles` contains kitchen AND `carrying.kind === "kitchen"` simultaneously after step 4.

### Same root cause, silent data loss
Because `pickUp` never records history and the carried tile is simply absent from `home` in memory, any *other* write while a tile is being carried (place/remove/rotate elsewhere) persists `home.json` **without** the carried tile. If the process dies in that window, the tile is gone — not just "unsaved," actually lost, since nothing on disk or in `carrying` survives a process restart (module-level `build` state is wiped). This only looked safe in my first pass because I only checked the case of quitting *immediately* after pickup with no intervening write.

### Also flagged by the grader, worth fixing alongside
- `saveHome` (`tui/home.ts`) has no try/catch, unlike the pattern elsewhere in this file's sibling (`writeState`) — a read-only config dir throws inside a key handler and can crash the whole TUI via the uncaughtException handler, not just build mode.
- `loadHome` doesn't validate tile shape (`if (Array.isArray(j?.tiles)) return { tiles: j.tiles }`) — a malformed `home.json` (e.g. `{"tiles":[{}]}`) loads tiles with no `kind`/`at`, which then breaks `connected`/rendering downstream.
- No test exercises the main.ts glue (write-only-when-`writes`-changed, `undo`'s unconditional save, or any carry+mutate-elsewhere interaction) — this is exactly the gap that let the duplication bug through.

### Suggested fix (from the grader, which I agree with)
Make `place`, `remove`, `rotate`, and `undo` no-op (return `b` unchanged) while `b.carrying` is set — carrying should block every other mutation until the tile is dropped. Add a test: pickUp, then attempt place/remove/undo elsewhere, assert the carried tile is unaffected and appears exactly once across `home.tiles` ∪ `carrying`. Separately: wrap `saveHome` in try/catch, and validate loaded tiles' shape against `CATALOGUE` and `at` being a numeric pair.

Sending back to build.
