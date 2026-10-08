VERDICT: approve

Read the diff (main...HEAD, office/ only, 4 files). I did not re-run the gate; the server's verify recorded `mise run check` green.

1. applyBuild (tui/home.ts): saves only when `writes` changed, and main.ts now calls it. The save is injectable, so the spy tests cover pick-up/move (no save), refused drop (no save), successful drop (one save), and place plus undo (two saves).
2. place() keeps `rot` when it cycles the kind. `existing?.rot` is falsy for rot 0 or undefined, so the tile stays unrotated, which is the same result. The test covers rot 90.
3. gridWindow/GRID_MAX: under the cap it matches the old tiles-plus-cursor-plus-margin box. Past the cap it centres a window on the cursor, so the cursor always stays inside and the size is capped. The test checks the cap and containment for three far cursors. Tiles outside the window are not drawn, which is an acceptable tradeoff.

Nits, not blocking: the cap test only runs far-cursor cases. A cursor near the cap boundary, 14 to 16 cells, would be a cheap extra case.