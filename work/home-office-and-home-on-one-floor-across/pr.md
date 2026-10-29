# Office and home on one floor across a street — part (a), the floor (#602)

`home.json` tiles now mean absolute floor cells below the office instead of a strip hung under it.
- `kit/home.ts`: `CELL`, `OFFICE_ROWS`, `cellPx`, `floorHeight`; `belowOffice` shifts a pre-floor file in memory only (`loadFloor`); `defaultHome` (street row + rooms); `HOME_BLOCKS`/`tileBlocks`; `cellPath`; build mode takes a `top` row and refuses drops above it.
- `kit/homeart.ts`: `paintFloor` replaces `paintAnnex` (no pad, no rebasing); the build grid leaves the office rows unpainted.
- `kit/floor.ts`: `floorPlan(home, w, floor)` adds the home tiles' blocks and, with a street under the front door plus a living tile, `doors` and `walk` (anchors for part (b)).
- `rooms/wide.ts`: height is the floor's real extent; `setHome` re-plans the sim (skipped when unchanged).

Part (b), the walk (figure, `h`/`o`, clock), is a separate build on top.

Checked: `bun test` on home/homeart/wide/floor (golden unchanged, no home → same frame); route test now also runs over a composed floor; `bun run typecheck`; `mise run office:check` via run_task (result on the thread). Live drive-office check not done by the builder.
