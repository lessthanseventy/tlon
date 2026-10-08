REQUEST_CHANGES (supersedes my earlier approve — grader caught a real bug I missed)

Reviewed the 5-commit diff on work/floor-step-3-build-mode-and-the-first-ho against main (office/kit/home.ts, office/test/home.test.ts, office/tui/home.ts, office/tui/main.ts).

**Bug: `remove()` has no connectivity check, unlike `drop`/`place`**

office/kit/home.ts's module comment states the invariant as "the floor stays one piece, or the drop is refused," and `drop`/`place` both gate through `canPlace` (which requires `connected()` on the *whole* resulting tile set). `remove()` does not:

```
export function remove(b: Build): Build {
  if (b.carrying) return b
  const tile = at(b.home, b.cursor)
  if (!tile) return b
  return { ...b, home: { tiles: b.home.tiles.filter((t) => t !== tile) }, history: remember(b), writes: b.writes + 1 }
}
```

Traced the consequence: living(0,0)-kitchen(1,0)-bathroom(2,0), remove the middle tile → home is now two disconnected single tiles, persisted to home.json with no refusal. From there, `canPlace` requires the *entire* post-drop tile set to be connected, so once the floor is split, almost every future `place()`/`drop()` is refused (only a drop that exactly bridges the gap succeeds). Because `place`/`remove`/`rotate`/`undo` are all blocked while `carrying` (by design, to stop the carried tile being lost/duplicated), a player who picks up a tile off an already-disconnected floor has only `move`/`drop` left — and in configurations with more than one gap or a distant island, no drop reconnects everything, so the tile can't be placed back anywhere. That's a genuine soft-lock, not just a cosmetic gap.

**Fix** (per the grader's proof, which I agree with):
- In `remove()`, compute the tiles without the target and refuse (`{ ...b, refused: true }`, no write) if `!connected(rest)`.
- Add a test: living(0,0)-kitchen(1,0)-bathroom(2,0), remove at (1,0) → refused, 3 tiles still there.
- Add a test: pick up a tile and drop it back at its own original cell → succeeds (guards against a regression where `canPlace` rejects a no-op drop).

**Also flagged, non-blocking but worth picking up in the same pass:**
- `tui/main.ts`'s wiring (`saveHome` only called when `writes` changes, the key bindings) has no test — drive-office coverage (press B, n, esc; check `home.json` via `TLON_HOME` holds one tile; press B, Enter to pick it up and confirm the file is unchanged) would close that gap.
- Grid render in build mode is unbounded by cursor distance from the floor (noted in my first pass, still true).
- `place()`'s kind-cycle drops `rot` on the cell (noted in my first pass, still true).

Sending back to build for the `remove()` fix and its two tests; the rest can ride along if convenient but isn't a blocker on its own.