APPROVE — Uqbar step 4 marginalia, re-reviewed at adccadb (one commit since my 71b3136 request_changes; branch is 20 commits on top of origin/main, rebased).

What adccadb does: `Measure` gains `rowHeight` (a terminal cell row in room px, `g.ch/g.k` in both kitty and half-block modes, set in `measureFor`), and `marginInk` sizes the hit's reach below the baseline from it instead of from `lineHeight`. Under kitty `lineHeight` was the bitmap font's pitch, so `below` stayed 2 px and the row holding the baseline lit the NEXT note; now it is half a cell row wherever the terminal draws. The sweep test gains three kitty geometries (k=3, 3, 4) beside the four half-block ones. This is the patch I escalated last round, with one difference: it extends the box only below the baseline, not above as well. That is enough — the box already reaches 7 px above, and half a cell row is ≤ 4 px at k≥2, so every geometry in the test is covered either side.

Verified at the tip:
- `bun test test/margin.test.ts`: 11 pass / 0 fail. `tsc --noEmit` clean.
- My probe from last round (two notes, viewport heights 80..299, hover the row holding each baseline at its first column) re-run against the tip: wrong-note hits are 0 on every geometry — kitty 150×60 10×20 k=3 (the operator's ghostty geometry) 0 wrong / 0 unreachable; kitty 100×40 12×24 k=3 and half blocks 150×60 0 wrong. Last round the k=3 row lit the wrong note 88/440 times and Enter opened the wrong thread; that is gone.
- Full office suite through cap: 406 pass / 3 fail, the three tmux-in-sandbox tests (EROFS on /tmp/tmux-1000), the same three as every previous round, not touched by this change.

Not blocking (follow-up re-filed): when a cell row is taller than the 9 px line pitch (kitty k=1, or k=2 with cells ≥ 20 px) two baselines share one row, so one note has no row of its own and stays unreachable (kitty 8×16 at k=2 in my probe). A layout question — space margin lines by the cell pitch under kitty — not a hit-box one.

Advancing to the merge gate.