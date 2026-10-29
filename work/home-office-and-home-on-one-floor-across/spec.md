# Home: office and home on one floor across a street, with the clock-out walk (#602)

Source: `docs/plans/2026-10-06-home-space-and-dollhouse-design.md` §2.2, §3.3, §8 step 5. One spec,
two builds that stack: **(a) the floor** lands first, **(b) the walk** is its own build on top of it
(same files, so never parallel). Nothing here is on main yet.

## What exists (read from the tree)

- `kit/floor.ts` `floorPlan(home, w)` builds the sim's Plan from **office** tile kinds only
  (`FACTORIES`); home kinds (`living kitchen bathroom bedroom street garden`, `kit/home.ts`) are not in it.
  Its header says `at` is read but not applied.
- The home is drawn by `kit/homeart.ts` `paintAnnex` as a strip under the office: `WideRoom.height =
  WIDE_H + annexHeight(home)` (`rooms/wide.ts`), tiles positioned relative to the home's own
  min `at` (`bounds`), padded by `ANNEX_PAD`. The sim never sees it; nobody can walk there.
- `tui/viewport.ts` already pans/clamps/edge-marks a floor taller than the terminal; `tui/main.ts`
  holds `homeNow = loadHome()` and re-reads it live; build mode (`b`-less today: opened elsewhere in
  main.ts ~1579) edits `home.json` through `kit/home.ts`.
- **There is no operator figure in the sim** (no `operator` in `kit/sim.ts` / `rooms/wide.ts`), and no
  `h`/`o` keys, no `clock_out`/`clock_in`. Part (b) must create the figure; it is the bulk of (b).

## Part (a) — one coordinate space, the street between

**Goal:** office and home are one floor; `home.tiles[].at` means absolute floor cells.

Decisions:
1. **Grid.** Cell = `CELL` (homeart). The office is a fixed block at the floor origin, `ceil(w/CELL)` x
   `ceil(WIDE_H/CELL)` cells, drawn exactly as today (golden frames unchanged for the office rows).
   Home tiles occupy cells with `y >= officeRows`; a tile whose cell overlaps the office block is
   refused by build mode (`canPlace`) and, on load of an old file, shifted down so its topmost row sits
   on `officeRows + 1` (in memory only; the file is rewritten only when build mode saves).
2. **Street.** The `street` tile (already in the catalogue) is the connector. Default home preset puts a
   one-row street directly under the office, spanning the office width, with the home tiles below
   it. The office door (`plan.door`/`exit`, front door at `w-18`) opens onto the street row; the home
   door is the `living` tile's top edge. If the first build is too much map, the street gets shorter, not cut (§9).
3. **Rendering.** `paintAnnex` becomes `paintFloor`: draws home tiles at `at * CELL` in floor
   coordinates (no min-`at` rebasing, no `ANNEX_PAD`), street included; `height` = `max(WIDE_H, bottom of
   lowest tile)`. The viewport/`geometry` need no new idea, only the new floor size.
4. **Sim.** `floorPlan` gains the home tiles' blocks and spots offset by their origin (§2.2): `blocks`
   = office blocks + each home tile's footprint at its cell; routes between the office and the street
   go through the front door waypoint, street -> home door via a door graph over home tiles (BFS across
   open edges, waypoint at door midpoint). Home tiles may have no spots yet; the street tile exposes
   `door-office` and `door-home` anchor points (used by (b)).
5. **Build mode** keeps working: cursor/grid window now in absolute cells, so the office block is shown
   dimmed and non-placeable.

**Files:** `kit/floor.ts`, `kit/home.ts`, `kit/homeart.ts`, `rooms/wide.ts`, `tui/main.ts` (grid window,
legacy-shift on load), `tui/viewport.ts` only if clamping needs the taller floor.

**Done when** (each is a test, written first):
- `test/wide.test.ts` passes unchanged: every route between every spot through every block, on the
  composed floor and per tile (extended to include home tiles' blocks).
- New: with a tile at `[0, officeRows+1]` the sim's `blocks` contain its footprint at the offset;
  a tile at `[2, officeRows+1]` is offset by `2*CELL` in x.
- New: office rows of `render` are byte-identical to the golden hashes (`test/golden.ts`) with and
  without a home; `render().height` grows by the home's real extent, no `ANNEX_PAD`.
- New: legacy `home.json` (tiles at `[0,0]..`) loads shifted below the office; the file on disk is untouched.
- New: build mode refuses a drop overlapping the office block.
- Verify: `mise run office:check` (unsandboxed; `OFFICE_TEST_HOUR=3` and `=15` for day/night), then `drive-office`: pan to the street and read the header back.

## Part (b) — the walk (waits for (a))

**Goal:** the operator's figure lives on the floor and crosses the street; four things move it (§3.3).

Decisions:
1. **The figure.** One operator actor in the sim ("you"), home spot = `bed` or `living` tile when
   home, your desk when at the office; drawn with the operator's look (`looks`), clickable like any
   actor. Where you are = `office | home | walking`, held in the sim, exposed as `plan`-agnostic state.
2. **Walk plans.** `route(from, goal)` already joins tiles via doors; a walk is that route from the
   figure's spot to the other side's anchor (`door-office` -> `door-home`), stepping at normal speed;
   `h`/`o` fast-walk (the same path, ~4x speed) while the viewport jumps to the destination at once.
3. **Four movers:**
   - **Clock:** `home.json` `"clock_out": "18:00"`, `"clock_in": "09:00"` (HH:MM local, optional, re-read live); at the time the figure sets off and the viewport follows (re-centres each frame until arrival).
   - **Keys:** `h` home, `o` office (`tui/main.ts` keymap; check for clashes, `b` is already memory).
   - **Attention:** opening a thread, a terminal or lazygit -> office; stamping a routine or opening the
     life card (`L`) -> home. Attention overrides the clock only for that moment: an explicit key or
     clock event wins over a later attention event for 60 s (no tug of war).
   - **Coworkers cross:** a consult (`Visit`) or nag walks the coworker to the home door and rings
     (the doorbell, #32, stays held until this lands; (b) provides the crossing, not the bell).
4. **While you are home** the office keeps running (desks, queue at your door); the needs count in the
   header is unchanged. A balloon for someone off-screen is already an edge marker (`clipFrame`).
5. **Sim touchpoints:** `kit/sim.ts` (operator actor, walk plan, goal override), `kit/floor.ts`
   (walk routes, anchors), `kit/home.ts` + `tui/home.ts` (parse `clock_*`), `tui/viewport.ts` (follow
   the walk), `tui/main.ts` (keys, attention hooks, clock tick), `tui/paint.ts` (nothing structural).

**Done when:**
- Unit: parse `clock_out`/`clock_in` (valid, absent, malformed -> ignored); a fake clock at 18:00 sets the
  figure's goal to home; at 09:00 back to the office.
- Unit: the walk route from desk to living tile is a path through `door-office`, the street, `door-home` and
  hits no block (reuse the wide.test route walker).
- Unit: attention events map to a side; an explicit `h` is not undone by an attention event within 60 s.
- **The walk is seen, not assumed** (§8): a `drive-office` session — press `h`, read the screen back
  mid-walk (figure on the street row, viewport moved) and after (figure in the living tile); press `o`
  back; set `clock_out` to now+1 min in a scratch `TLON_HOME` and watch it leave. Screen text pasted into the PR.
- `mise run office:check` green; `wcag.test.ts` still passes at every viewport position.

## Where it splits

(a) ends when the floor is one coordinate space with a walkable street, no figure. (b) starts by
adding the operator actor on that floor. Both touch `floor.ts`, `home.ts`, `viewport.ts`, `main.ts`, so (b) branches from (a)'s landed main. Two PRs minimum; (a) is also split if >1 review: (a1) coordinates + render, (a2) sim blocks/routes.

## Out of scope
Doorbell (#32), routine/quest tiles, XP header, §6 presets beyond the default, pets crossing, server changes (everything here is office-side files; `home.json` stays the surface's, not server state).

## Open for the operator (defaults chosen; say if wrong)
- Street default: one row, full office width.
- Legacy `home.json` is shifted below the office on load, not rewritten.
- Operator figure at the office = your desk; at home = the living tile.
- 60 s attention-lock after an explicit `h`/`o`/clock event.
