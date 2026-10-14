## Verdict: approve

Re-review of work/savehome-a-placed-tile-drops-the-hidden at 2aca8ac (round 2). Nothing changed since the first verdict — `git diff 2aca8ac..work/savehome-a-placed-tile-drops-the-hidden` is empty; the branch HEAD is still the review commit. The verify gate passed (`mise run check` exit 0, recorded by the server), and QA's live drive on the :4122 scratch release confirmed the fix end-to-end: TLON_HOME seeded `{"tiles":[{"kind":"not-a-kind","at":[1,0]}]}`, placed `kitchen` on [1,0], read back exactly `{"tiles":[{"kind":"kitchen","at":[1,0]}]}` — no `not-a-kind`, no duplicate, repeated with the same result. Caveat logged by QA: not run on the pre-fix build, so it shows fixed behaviour, not a before/after; the unit test is the before/after proof.

### Spec compliance
office/tui/home.ts:37-40 — a `Set` of `"x,y"` from the known tiles being saved, then `unknownTiles(path).filter(...)` drops any hidden tile whose `at` joins to a member of that set. Minimal and surgical; touches nothing else. The placed known tile wins its cell, exactly as ticket #140 / the decision asked. Hidden unknowns on free cells are still carried through load/save unchanged.

office/test/home.test.ts:176-184 — unknown kind at [1,0], save kitchen at [1,0], assert the file holds exactly `[{ kind: "kitchen", at: [1,0] }]`. The test reads the raw JSON, not `loadHome` — the right choice, since `loadHome` filters unknown kinds and would mask whether the drop actually happened.

### Correctness
A malformed hidden tile (missing or non-array `at`) resolves to `""` via `?.join(",") ?? ""`, which never matches a real known cell, so a cell-less hidden tile is carried rather than dropped or crashed on. Safe. The placed-known-wins direction is the only one that needed fixing; two hidden unknowns on the same cell are untouched (out of scope, harmless — both opaque).

### Gate
office suite green; typecheck exit 0; home.test.ts 28/28. `mise run check` green on the branch (verify evidence recorded).

No follow-ups.