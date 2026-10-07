## Verdict: APPROVE

Branch implements spec.md/plan.md's ten-task cut faithfully. Ran `mise run office:check` and drilled into the two failures it reported; neither is a defect introduced by this diff.

### Spec compliance — verified
- No `as any` anywhere in `kit/floor.ts` or `kit/tiles.ts` (spec's explicit task-10 requirement). `floorPlan(home, w)` is fully typed, builds each `Plan` array via `tiles.flatMap(t => t.spots(l)[kind] ?? [])` as the plan prescribed, not a cast.
- Golden-frame test (`test/wide.test.ts`) has five real 64-char sha256 hashes (540/560/640/696/900), not placeholders; passes in isolation in 460ms, pixel-identical through all ten commits.
- Per-tile "no spot inside its own blocks" walkability test present and green; composed-floor furniture-walk test green (4/4 route tests pass).
- Games tile owns arcade/ping-pong/foosball/pool/aquarium per spec's ownership table — confirmed as the judgment call build (hronir) flagged mid-stream, correctly resolving plan.md's stale "other tiles" prose in favor of the approved spec table.
- `Tile.draw` extended with a `Live` context (sim.cat, `at`/`using`/`actor`) beyond the original sketch — documented necessity (pastime art reacts to live state), confined to `kit/tiles.ts`, doesn't leak into the `Home`/floorPlan composition contract.
- `widePlan = (w) => floorPlan(DEFAULT_OFFICE, w)` — the one-liner the plan asked for.
- `DEFAULT_OFFICE`'s tile order (`lounge` before `office`, etc.) differs from spec.md's illustrative `home.json`, but is deliberately chosen and commented to preserve the original array's spot-ordering tie-break (idle-target order is load-bearing per `kit/floor.ts`'s own comment) — the golden-frame hash proves this is pixel/behavior-identical, so the deviation is justified, not a slip.

### Two test failures seen under `mise run office:check` — neither blocks
1. **`test/terminal.test.ts` EPIPE** — a tmux control-mode broken-pipe failure. File untouched by any commit on this branch; reproduces identically run alone, unrelated to the tile cut. Pre-existing environment flake.
2. **`wide.test.ts`'s antics test timeout (>5000ms)** — passes reliably in isolation (1.7–2.3s, well under its default timeout). Only times out when the full suite runs concurrently, consistent with the *sibling* zoomies test's own comment ("more [CPU] when the gate runs every suite at once" — which is why that test carries an explicit `30_000` timeout override). The antics test lacks that override on **both** main and this branch; this diff doesn't touch its timing-sensitive code path (`stepAntics`/`petRoom` logic is unmodified, still lives in `wide.ts` per spec's non-goals). Not a regression this PR introduced — but worth a follow-up ticket to give it the same explicit timeout bump as its neighbor, since it's a latent flake independent of this work.

No bugs or spec deviations found in the diff itself. Approve for merge.