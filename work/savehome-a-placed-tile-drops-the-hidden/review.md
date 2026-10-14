## Verdict: approve

Round 3 — re-review of work/savehome-a-placed-tile-drops-the-hidden at 4fcffae, the malformed-`at` fix on top of 2aca8ac.

### What changed since the last verdict (f1f4be4)
`git diff f1f4be4..4fcffae` — two files:
- `office/tui/home.ts`: the hidden-tile filter now guards `Array.isArray(at)` before calling `.join`, so a non-array `at` no longer throws.
- `office/test/home.test.ts`: a new test seeds `{"kind":"not-a-kind","at":"x"}`, saves a `kitchen` at [1,0], and asserts the file holds both.

### Correction to the round-2 review
My round-2 review claimed a malformed hidden tile "resolves to `""` via `?.join(",") ?? ""`… Safe." That was wrong. On a string `at` (e.g. `"x"`), `at?.join(",")` evaluates `"x".join(",")` — strings have no `.join` method, so it throws `TypeError`, the surrounding `catch` swallowed the entire save, and the placed kitchen tile was lost too (not just the hidden one). QA's live drive on the :4122 scratch release caught this: seed `{"tiles":[{"kind":"not-a-kind","at":"x"}]}`, place kitchen, save, read back — file unchanged. This commit is the fix for that exact regression.

### Correctness
`office/tui/home.ts:39-42`:
```
const hidden = unknownTiles(path).filter((t) => {
  const at = (t as { at?: unknown }).at
  return !(Array.isArray(at) && cells.has(at.join(",")))
})
```
- `at` is an array and `cells` has it → `!(true && true)` = false → dropped. Placed known tile wins its cell, per ticket #140 / decision #2049.
- `at` is an array and `cells` does not have it → `!(true && false)` = true → kept. Hidden unknowns on free cells pass through unchanged.
- `at` is non-array or missing → `!(false && …)` = true → kept, and `.join` is never called, so no throw. The save completes; the placed known tiles are written. Matches decision #2111 (kitchen at [1,0] saved, `at: "x"` tile preserved).

`cells` itself (`home.tiles.map((t) => t.at.join(","))`) is safe: `home.tiles` are `HomeTile`, whose `isTile` guard requires `at` to be a length-2 number array, so `.join` there cannot throw.

### Test
`office/test/home.test.ts:185-195` — seeds the malformed hidden tile, saves a kitchen on [1,0], reads the raw JSON (not `loadHome`, which would filter the unknown kind and mask the result), asserts both tiles present. This is the before/after proof: it failed RED on the unfixed file (the save threw and the file stayed `{"kind":"not-a-kind","at":"x"}`) and passes GREEN with the guard. The round-2 test (hidden `[1,0]` dropped on a placed kitchen) still holds alongside it.

### Gate
`office/test/home.test.ts` 29/29 (bun test). `mise run check` exit 0 on the branch — verify evidence recorded by the server at 18:47:37. QA re-drove the malformed-`at` case on the rebuilt :4676 scratch release per decision #2111 (build_mode enabled on :4676 only, never :4040).

### Spec compliance
Surgical: 4 lines of logic + one test, touching nothing outside the cell filter. The placed-known-wins direction is the only behaviour changed; two hidden unknowns on the same cell remain untouched (out of scope, harmless). The fix narrows the drop to tiles whose `at` is a real cell, so a cell-less hidden tile is now carried rather than silently lost — a strict improvement over the round-2 behaviour.

No follow-ups.