# Floor step 1 — plan

Ten commits, each green on `mise run office:check` before the next starts. Read `spec.md` first —
this plan doesn't repeat the tile-ownership table, the `Tile`/`Home`/`floorPlan` type sketches, or
the design rationale; it turns each of the spec's ten tasks into exact files and an exact
red→green sequence.

All paths below are relative to `office/`.

## Task 1 — golden-frame tripwire, seeded, captured from today

**Files**: `test/wide.test.ts` (edit).

1. Add the import `import { createHash } from "node:crypto"` at the top.
2. Add this test, inside `describe("the wide room", ...)`, with a placeholder hash table:
   ```ts
   test("the room's pixels don't move: a golden hash per width", () => seeded(1, () => {
     const golden: Record<number, string> = { 540: "x", 560: "x", 640: "x", 696: "x", 900: "x" }
     for (const [w, hash] of Object.entries(golden)) {
       const room = new WideRoom(Number(w)), a = viewOf(office(6), 1)
       for (let i = 0; i < 300; i++) room.step(a)
       const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
       const got = createHash("sha256").update(Buffer.from(fr.rgba)).digest("hex")
       expect(got).toBe(hash)
     }
   }))
   ```
3. Run it (`bun test test/wide.test.ts -t golden`); it fails, printing the actual hash for each
   width in the diff. Copy each actual hash into `golden`, replacing the `"x"` placeholders.
4. Re-run; it passes. This is the baseline — the unmodified `wide.ts`'s render, hashed, under the
   fixed seed.
5. Commit: `test: a seeded golden-frame hash per width, the tripwire for the tile cut`.

**Done**: `bun test test/wide.test.ts -t golden` green, against unmodified `wide.ts`.

## Task 2 — `kit/tiles.ts`: the types, no logic

**Files**: `kit/tiles.ts` (new).

Write exactly the `TileKind`, `Rect`, `Tile<L>`, `Home` types from spec.md's "`kit/tiles.ts` (new)"
section. No test — nothing imports it yet, so there's no behavior to assert. Typecheck with
`bun run tsc --noEmit` (or whatever `office:check` runs).

Commit: `tiles: the Tile, Home and TileKind types — no logic yet`.

**Done**: typechecks clean; `bun test` still green (nothing changed behaviorally).

## Task 3 — Argos lifted to `kit/pets.ts`

**Files**: `kit/pets.ts` (new), `rooms/wide.ts` (edit).

1. In `wide.ts`, find: the `Dog` type (`type Dog = { ... }`), the `ARGOS` dialogue object, and the
   methods `dogBed`, `dogBowl`, `dogDo`, `patDog`, `fussDog`, `stepDog`, `drawDog` on `WideRoom`.
2. Move the `Dog` type and `ARGOS` object verbatim into `kit/pets.ts`, exported.
3. Move each method's **body** into `kit/pets.ts` as a standalone exported function, with `this`
   replaced by explicit parameters:
   - `dogBed(bed: Spot)` → stays a pure function of the spot the room hands it (the room still
     computes `this.z.L0 + 108, 112` etc and passes the `Spot`; `kit/pets.ts` doesn't know about
     `Zones`).
   - `dogBowl(bowl: Spot)` → same.
   - `stepDog(d: Dog, ctx: { tick: number; actors: ...; plan: Plan<unknown>; quiet(u: number): boolean; argos(...): string; fussDog(...): void; ... })` — the exact `ctx` shape is whatever
     `stepDog`'s body actually reaches for on `this`; keep it as one object so the call site in
     `wide.ts` stays a single line (`stepDog(this.dog, this)` works if `WideRoom` structurally
     matches — prefer that over hand-picking fields, it's less to keep in sync).
   - `patDog(d: Dog, say: (text: string) => void)`, `fussDog(d: Dog, by: Actor, say: ...)`,
     `drawDog(sc: Scene, d: Dog, bed: Spot, bowl: Spot)` similarly.
   - `argos(occasion, name)` — the little dispatcher reading `ARGOS`/`ARGOS.fuss` — moves too, as a
     plain exported function (it doesn't touch `this` beyond calling the room's `line()`, so take
     `line` as a parameter).
4. `WideRoom` keeps `private readonly dog: Dog` as a field, assigned via `kit/pets.ts`'s exports in
   its constructor and `step`/`render`, calling the moved functions instead of `this.stepDog()`
   etc. The field's **name and shape must not change** — `test/pets.test.ts` and
   `test/wide.test.ts` cast `room as unknown as { dog: ... }` directly.
5. `stepAntics`, `drawAntics`, and the `Antic` type **stay in `wide.ts`** — they read both `this.cat`
   and `this.dog` and are the room's own choreography (spec.md says so explicitly).
6. Run the suite. `test/pets.test.ts`, and `test/wide.test.ts`'s two Argos-furniture-collision
   tests ("Argos keeps off the furniture, and gets around" / "Nina and Argos get up to things…"),
   plus the task-1 golden-frame test, must all still pass unchanged — this is a pure relocation,
   zero behavior change.

Commit: `pets: Argos' data and behavior lifted to kit/pets.ts`.

**Done**: golden-frame green; `test/pets.test.ts` green; the two Argos furniture tests in
`test/wide.test.ts` green; nothing in any test file changed except imports.

## Task 4 — `games` tile

**Files**: `kit/tiles/games.ts` (new), `rooms/wide.ts` (edit), `test/wide.test.ts` (edit, add the
per-tile walkability test — see task 9, written once and extended tile by tile as each exists; add
the `games` case here).

1. In `wide.ts`, locate: the `cabinets`/`tank` fields of `corner(z)` (the arcade cabinets, the
   aquarium — not `table`, `vending`, `shelf`, `foos`, `pool`, which belong to other tiles), the
   `lounge[]` array entries for `arcade`, `pingpong` (both ends), `aquarium` (both spots), the
   `blocks()` entries `table, ...cabinets, tank` *(table here is the ping-pong table — it's
   `games`'s, not `kitchen`'s or `lounge`'s)*, `pastimes()`'s arcade/ping-pong/aquarium drawing
   blocks, `arcadeScores()`, `highScores()`, and the `highs`/`runs`/`fanfare` fields they use.
2. Write `kit/tiles/games.ts` exporting a factory `gamesTile(z: Zones, w: number): Tile<Layout>`
   whose `blocks`, `spots`, and `draw` reproduce exactly what moved — same pixel math, same
   `sc.item(...)` z-order values, so scene compositing is unaffected by which module pushed the
   item. `highs`/`runs`/`fanfare` become private state owned by the tile factory's closure (or a
   small class instance) rather than `WideRoom` fields; `WideRoom.highScores()` (used by
   `tui/main.ts`) forwards to the tile's own exposed getter — keep that method's public signature
   identical.
3. `wide.ts` calls `gamesTile(z, w)` once (constructed alongside the other tiles — see task 10 for
   where that construction ultimately lives; for tasks 4–9, construct it directly in `WideRoom`'s
   constructor/`render`/`step` as a stopgap, since `floorPlan` doesn't exist until task 10) and
   delegates to it instead of drawing those pieces inline.
4. Golden-frame must stay green — if any hash changes, the cut moved a pixel; diff the before/after
   frame to find which `px`/`blit` call lost its exact coordinates in the move.

Commit: `tiles: cut the games corner (arcade, ping-pong, aquarium) out of wide.ts`.

**Done**: golden-frame green; `highScores()` still reachable from `tui/main.ts` unchanged.

## Task 5 — `kitchen` tile

**Files**: `kit/tiles/kitchen.ts` (new), `rooms/wide.ts` (edit).

1. Locate: `corner(z).vending`/`.shelf` *(the snack machine and bookshelf are lounge's reading-nook
   furniture by the plan's grouping — re-check against spec.md's table: `vending` is listed under
   `kitchen`'s `lounge()` entries; `shelf` (the bookshelf + armchair/read spot) is `lounge`'s, not
   `kitchen`'s — move only `vending` here, leave `shelf` for task 6)*, the `cooler`/`coffee` spots
   in `lounge[]`, the kitchen-counter/fridge `blocks()` entry (`{ x: w - 14, y: 100, w: 14, h: 56 }`
   near line 200), and the `sc.item(156, ...)` block in `render()` that draws the cooler, coffee
   machine, and fridge (plus the matching `sc.item(v.y + v.h, ...)` vending-machine draw in
   `pastimes()`).
2. Write `kitchenTile(z: Zones, w: number): Tile<Layout>` reproducing it exactly.
3. Wire into `WideRoom` as task 4 did.

Commit: `tiles: cut the kitchen (cooler, coffee, vending, the counter) out of wide.ts`.

**Done**: golden-frame green.

## Task 6 — `meeting` tile

**Files**: `kit/tiles/meeting.ts` (new), `rooms/wide.ts` (edit).

1. Locate: `oncall: [...]` (the laptop spots), the meeting-room glass `blocks()` entries (the two
   `M0 - 1`/`M0 + MW - 1` glass strips, the two bottom-wall strips, the table block at
   `{ x: Mc - 14, y: 76, w: 28, h: 20 }`), and the `sc.item(BAND, ...)` + `sc.item(96, ...)` +
   `text("MEETING", ...)` draw calls.
2. Write `meetingTile(z: Zones, w: number): Tile<Layout>`. `oncall` is optional on `Tile`/`Plan` —
   this tile's `spots()` includes it; `floorPlan` (task 10) is responsible for surfacing it on the
   composed `Plan` only when a tile on the floor provides it (today's floor always does).
3. Wire in.

Commit: `tiles: cut the meeting room out of wide.ts`.

**Done**: golden-frame green.

## Task 7 — `lounge` tile (what's left of it)

**Files**: `kit/tiles/lounge.ts` (new), `rooms/wide.ts` (edit).

1. Locate what's left after tasks 4–5 took kitchen/games: the four `couch` spots, the two `window`
   spots, the two `plant` spots (the lounge's one — your office's stays with `cat-corner`/`office`,
   check the x-coordinate: `L0 + 22, 184` is lounge's, `18, 168` is the office-side one), the `chat`
   pair, the two `pet` spots, `shelf` (bookshelf) and the `read` spot, the couch-back `blocks()`
   entry, the rug/lamp/beanbag/bookshelf/armchair `sc.item(...)` draws, and the windows/plant-growth
   drawing in `pastimes()`'s bookshelf+armchair block and the watered-plant block (the *lounge's*
   plant only — `[this.z.L0 + 22, ...]`, not the office's `[18, ...]`).
2. Write `loungeTile(z: Zones, w: number): Tile<Layout>`.
3. Wire in.

Commit: `tiles: cut the lounge (couches, windows, plants, the reading nook) out of wide.ts`.

**Done**: golden-frame green.

## Task 8 — `cat-corner` tile

**Files**: `kit/tiles/cat-corner.ts` (new), `rooms/wide.ts` (edit).

1. Locate: `TOWER_X`, `PERCH_TOP`, `PERCH_MID`, `CAT_NAP`, `CAT_DESK`, `LITTER`, `PLAY`, `YARN`,
   `MOUSE`, `RADIATOR`, `CAT_WARM`, the cat-tower + radiator `blocks()` entries, the
   `ninasCorner()`-equivalent draw (the rug/tower art — confirm the exact call name against the
   current file; it's drawn around the `bossDesk`/office-furniture block, so isolate just Nina's
   pieces, not the boss desk), the radiator shimmer `sc.item(RADIATOR.y + RADIATOR.h, ...)` block,
   and the office-side half of `cat: CatPlan` (`nap`, `desk`, `play`, `litter`, `perches`, `warm`,
   the office entries of `leaps[0]`, the office entries of `spots`, and the office half of `via`).
2. Write `catCornerTile(z: Zones, w: number): Tile<Layout> & { cat: Partial<CatPlan> }` (or expose
   `cat()` as the spec's `Tile.cat?(l)` method — pick whichever reads cleaner once `office`'s half
   of `CatPlan` exists too, since the two halves merge in task 10).
3. Wire in — `WideRoom`'s `cat: Cat` field and `sim.ts`'s cat machinery are **unchanged**; only the
   room-specific `CatPlan` fragment moves.
4. Run `test/wide.test.ts`'s zoomies test ("Nina gets the zoomies…") and the antics test ("Nina and
   Argos get up to things…") — both read `plan.cat`, so they're the regression check for this cut
   specifically, on top of the golden frame.

Commit: `tiles: cut Nina's corner (tower, perches, litter, the radiator) out of wide.ts`.

**Done**: golden-frame green; the zoomies and antics tests green.

## Task 9 — `office` tile (everything left)

**Files**: `kit/tiles/office.ts` (new), `rooms/wide.ts` (edit), `test/wide.test.ts` (edit — add the
per-tile walkability test from spec.md, now that all six tiles exist to run it against).

1. What's left: boss desk + decor, in-tray, beacon, crew board, manager/lead desks (`execDesk`
   calls), the two tables of 4, filing cabinet, server rack, the "finished work" box drawing, the
   office glass wall, the `queue[]` spots, `home(l, agent)`, and the office-side half of
   `CatPlan.via`'s non-cat-corner branches (none — `via` is entirely cat-corner's; double check
   when you get there and fold it all into task 8 if so).
2. Write `officeTile(z: Zones, w: number): Tile<Layout>`. `home()` becomes this tile's own function
   of its `Layout` slice (desks + chairs) — `floorPlan` (task 10) is the one that knows `home` is
   `office`'s to provide.
3. Wire in.
4. Add the per-tile walkability test (spec.md's "no spot inside its own blocks" test) to
   `test/wide.test.ts`, iterating all six tile factories now that they all exist. This is the
   second half of the ticket's "every route through every block" check (the first half — the
   composed floor — already exists and keeps passing throughout).

Commit: `tiles: cut what's left of the office (your desk, the crew board, the floor) out of wide.ts`.

**Done**: golden-frame green; the new per-tile walkability test green for all six kinds; `wide.ts`
now has no inline furniture/spot/block code left outside `WideRoom`'s shared chrome (back wall,
hallway, exit, pen/box, antics) and the six tile modules.

## Task 10 — `kit/floor.ts`, `DEFAULT_OFFICE`, real `floorPlan`

**Files**: `kit/floor.ts` (new), `kit/tiles.ts` (edit — add `DEFAULT_OFFICE: Home`), `rooms/wide.ts`
(edit — delete the stopgap direct-construction from tasks 4–9, replace with `floorPlan`).

1. In `kit/tiles.ts`, add:
   ```ts
   export const DEFAULT_OFFICE: Home = { tiles: [
     { kind: "office", at: [0, 0] }, { kind: "cat-corner", at: [0, 0] },
     { kind: "meeting", at: [0, 0] }, { kind: "lounge", at: [0, 0] },
     { kind: "kitchen", at: [0, 0] }, { kind: "games", at: [0, 0] },
   ] }
   ```
2. Write `kit/floor.ts`'s `floorPlan(home: Home, w: number): Plan<Layout> & { blocks: (l: Layout) =>
   Rect[] }`, fully typed (no `as any` — see spec.md's note on this), that:
   - builds `z = zones(w)` and the six tile instances named in `home.tiles` via a
     `Record<TileKind, (z: Zones, w: number) => Tile<Layout>>` lookup table (one entry per
     `kit/tiles/*.ts` factory from tasks 4–9);
   - unions `blocks(l)` across every tile;
   - unions `spots(l)` by `Kind | Pastime` key into the `Plan`'s flat `queue`/`lounge`/`oncall`/`box`
     arrays — each tile's `spots()` return only has the keys it actually owns (`office` has `queue`,
     `games`/`kitchen`/`lounge` have the `lounge` kinds, `meeting` has `oncall`), so build each
     `Plan` array as `tiles.flatMap(t => t.spots(l)[kind] ?? [])`, not a cast;
   - merges `cat-corner`'s `CatPlan` fragment with `office`'s (if `office` turned out to own any of
     `via`'s branches — see task 9's note) into one full `CatPlan`;
   - keeps `home`, `visit`, `roam`, `route` as the functions `widePlan` already has today (these
     are cross-tile routing logic, not any one tile's — they move into `floorPlan`'s own body,
     unchanged from today's `wide.ts`, parameterized by `z`/`w` the same way).
3. In `rooms/wide.ts`: delete the six stopgap tile constructions, replace with one call —
   ```ts
   export const widePlan = (w: number) => floorPlan(DEFAULT_OFFICE, w)
   ```
   — matching the plan's "one-line `widePlan = floorPlan(DEFAULT_OFFICE)`" (with `w` threaded
   through, since this room is still width-responsive).
4. `WideRoom`'s constructor becomes `super(widePlan(width))`, same as today.

Commit: `tiles: floorPlan composes the six tiles; widePlan is one line`.

**Done**: golden-frame green at every tested width; the composed-floor walkability test
("no walk crosses the furniture") green; the per-tile walkability test (task 9) green; the full
`mise run office:check` green end to end; no `as any` anywhere in `kit/floor.ts` or `kit/tiles.ts`.

## Out of scope here

Steps 2 (viewport) and 3 (build mode, the first home tiles, real grid placement) stack on this one
later, per spec.md's non-goals.
