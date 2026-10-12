REQUEST CHANGES — Uqbar step 4 marginalia, re-reviewed at b893ce4 (one commit since my 5d913cb approval).

What b893ce4 does: the note's hit box now reaches `max(2, lineHeight/2)` below the baseline, and a sweep test (4 half-block geometries × 40 viewport heights) asserts the cell row holding each note's baseline hits that note. Red before, green after; I reproduced both. For half blocks this is correct: there `measure.lineHeight` IS a cell row (`g.ch/g.k`).

Finding (blocking): the fix doesn't reach the live surface. Under kitty `measureFor(g).lineHeight` is the bitmap font's line height, not the cell row's, so `below` stays 2 px there and the box is still baseline-7..+2 — the same bug class QA failed on half blocks. Measured with the tip's own `geometry`/`hitAt`/`measureFor` (probe: two notes, viewport heights 80..299, hover the row holding each note's baseline at its first column):

| geometry | now: baseline row lights the wrong note | with the patch |
|---|---|---|
| kitty 150×60, 10×20 px cells, k=3 | 88/440 (lights the NEXT note → Enter opens the wrong thread) | 0 |
| kitty 100×40, 12×24 cells, k=2 | 108/440, 90 unreachable | 72 / 54 |
| kitty 80×40, 8×16 cells, k=1 | 137/440, 137 unreachable | 109 / 95 |
| half blocks 150×60 and 100×40 | 0 | 0 |

This predates b893ce4 (the old 9 px box has the same gap), so it is not a regression — and it means my 5d913cb review's "the box covers the glyph under kitty" was wrong; I had not measured it. The k=3 row is the operator's realistic ghostty geometry and the symptom is worse than a miss: the wrong thread opens.

Fix (verified on a scratch copy of office/: new test red on the tip's margin.ts, green patched; full office suite 406 pass / 3 fail — the same three tmux-in-sandbox tests the tip fails; `tsc --noEmit` clean): give `Measure` a `rowHeight` (a terminal cell row in room px, `g.ch/g.k` in both modes) and size the hit half a row either side of the glyph, so the box always spans at least one row pitch wherever the baseline falls. Patch posted on the thread (canvas.ts Measure type, paint.ts measureFor, margin.ts marginInk, margin.test.ts sweep gains three kitty geometries at k=3,3,4).

Not blocking (follow-up filed): when a cell row is taller than the 9 px line pitch (kitty k=1, or k=2 with cells ≥ 20 px) two baselines can share one row, so one note has no row of its own and stays unreachable (the k=1/k=2 residue above). That is a layout question — space margin lines by the cell pitch under kitty — not a hit-box one.

Also checked: rebase state unchanged since last round; `bun test test/margin.test.ts` at the tip 11 pass / 0 fail.