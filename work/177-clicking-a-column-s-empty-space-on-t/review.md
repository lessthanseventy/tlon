APPROVE — #177: a column's empty space opens the column.

Read the diff (office/rooms/rail.ts, office/rooms/wide.ts, office/test/board-hits.test.ts, pr.md). I did not run the tests; the gate does.

- Rail: the background hit (x0-1, y11, w22, h12) is pushed after the stickies and the pen hit, so first-match keeps every sticky and the new-ticket pen intact. It ends at y23, and the notes strip starts at y24, so there is no overlap.
- Wide: `below = 3 + lh*(shown+1) + 1` is the pixel after the last line hit (`y-lh+1 .. y+1`), so the two are contiguous. The hit ends at y38, before the pen hit at y38. A full column gives h <= 0, which matches nothing, so it is harmless.
- Tests: they check both directions. Every line and sticky still resolves to itself, and the blank cell resolves to the column. The Hit import fix in 2fc952e is fine.
- No AGENTS.md or doc is made stale by this change.

Nothing blocking, so there are no follow-ups.