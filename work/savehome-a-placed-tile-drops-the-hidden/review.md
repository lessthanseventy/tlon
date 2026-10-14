## Verdict: approve

The change does exactly what ticket #140 / tertius's decision asked: a placed known tile wins its cell, and `saveHome` drops a hidden unknown-kind tile whose `at` collides with it. Hidden unknowns on free cells are still carried through load/save unchanged.

### Spec compliance
- office/tui/home.ts:38-40 — a `Set` of `"x,y"` from the known tiles being saved, then `unknownTiles(path).filter(...)` drops any hidden tile whose `at` joins to a member of that set. Minimal and surgical; touches nothing else.
- office/test/home.test.ts:176-184 — unknown kind at [1,0], save kitchen at [1,0], assert the file holds exactly `[{ kind: "kitchen", at: [1,0] }]`. The test reads the raw JSON, not `loadHome` — the right choice, since `loadHome` filters unknown kinds and would mask whether the drop actually happened. RED-first per the builder.

### Correctness
- A malformed hidden tile (missing or non-array `at`) resolves to `""` via `?.join(",") ?? ""`, which never matches a real known cell, so a cell-less hidden tile is still carried rather than dropped or crashed on. Safe.
- The placed-known-wins direction is the only one that needed fixing; two hidden unknowns on the same cell are untouched (out of scope, and harmless — both are opaque).

### Gate
office suite 624/624 at OFFICE_TEST_HOUR=3 and =15; typecheck exit 0; home.test.ts 28/28. `mise run check` green on the branch (recorded by the server's verify). Nothing owed.

No follow-ups.