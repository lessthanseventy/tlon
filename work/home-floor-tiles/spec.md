# Floor step 1 — tiles under the office

Scope: Track Floor, step 1 of `docs/plans/2026-10-06-home-space-and-dollhouse-design.md` (§2, §8
row 1). Confirmed with Andrew (thread 132, msgs 2388/2395/2396): the six-way split.

## Goal

`rooms/wide.ts` today is one 1037-line floorplan. After this step it is six self-contained
**tile** modules plus a `floorPlan` that composes them, and a `home.json` that places exactly
those six tiles — so the room renders **pixel-identical to today, at every width**, and nothing
about the office *looks* different. This is scaffolding for steps 2 (viewport) and 3 (build mode),
not a visual change.

## Non-goals (deferred to later steps)

- A real non-overlapping cell grid. Plan §10 defers "cell size" to "after the first tile cut, by
  looking" — this step does **not** commit to a cell size. Tiles are constructed with the room's
  pixel width `w` (via the existing `zones(w)`) and draw in **absolute room coordinates**; each
  tile's `at` in `home.json` is `[0, 0]` for this step (no spatial offset is applied yet).
  `floorPlan`'s offset-by-origin composition (plan §2.2) becomes real once tiles actually move
  apart — step 3's build mode.
- The viewport, pan/follow, kitty-placement cropping (step 2).
- Pick-up/place/build mode, and the first home tiles (step 3).
- The full multi-species `Pet`/`Species` interface (plan §5.2) — that is step 7's. This step only
  relocates Argos' existing code into `kit/pets.ts`; the shape doesn't change.
- Any home-only `TileKind` (`bedroom`, `bathroom`, `living`, `gym`, `garden`, `street`, `hall`) —
  those ship at step 3.

## The six tiles, and what each owns

`TileKind` for this step: `"office" | "cat-corner" | "meeting" | "lounge" | "kitchen" | "games"`
(the plan's full union minus the home-only kinds).

Mapping from today's `wide.ts` (line numbers as read on `work/home-floor-tiles`, pre-change):

| Tile | Owns (spots / blocks / draw) | Lines today |
|---|---|---|
| `office` | boss desk + decor, in-tray, beacon, crew board, manager/lead desks (`execDesk`), two tables of 4, filing cabinet, server rack, the "finished work" box, office glass wall, `queue` spots, `home()` for desk/table seats, office-side `blocks` | 70–82, 96–115 (partial), 192–211 (partial), 433–460 |
| `cat-corner` | Nina's tower/perches/nap/desk-spot/litter/play/yarn/mouse, the radiator + its warmth spot, `cat: CatPlan` (nap/desk/play/litter/perches/warm/leaps[0]/spots subset), the cat-tower + radiator `blocks` | 85–94, 164–179 (office-side half), 195, 205, 437, 498–504 |
| `meeting` | the round table, its glass walls, "MEETING" label, `oncall` laptop spots, meeting-room `blocks` | 144 (`oncall`), 196–198, 462–471 |
| `lounge` | couch spots + rug/lamp/beanbag, windows, plants, the chat/pet/read pastime spots, `lounge()`'s couch/window/plant/chat/pet/read entries, couch `blocks` | 117–121, 131–134, 141, 473–481, 489 (partial) |
| `kitchen` | cooler, coffee, kitchen counter/fridge, `lounge()`'s cooler/coffee/vending entries, counter `blocks` | 122–123, 135, 200, 482–488 |
| `games` | arcade cabinets, ping-pong table, foosball, pool table, aquarium, `lounge()`'s arcade/pingpong/aquarium/foosball/pool entries, their `blocks`, `pastimes()`'s arcade/pingpong/foosball/pool/aquarium drawing, `arcadeScores()`, `highScores()` | 46–59 (`corner()`), 126–130, 136–140, 201–203 (partial), 206, 373 (`arcadeScores`), 395–490 (the games/aquarium parts of `pastimes()`) |

**Stays in `WideRoom` (shared chrome, not any one tile's)**: the back wall band and everything on
it — calendar, whiteboard, corkboard, suggestion box, windows-weather, season, TV, clock — the
hallway, `exit`, `pen`/`box` spots, Nina's cat *simulation* (`sim.ts` is unchanged this step; only
her *room-specific* spots move into `cat-corner`'s `CatPlan` fragment), and the Nina/Argos antics
(`stepAntics`, `drawAntics`, `Antic` type) — that choreography is the room's own, not a pet's or a
tile's. `zones()` and `corner()` stay as the shared width-responsive geometry every tile factory
reads from (see below).

## `kit/tiles.ts` (new)

```ts
// A tile is a room module: its footprints, its spots, and how to draw it, in absolute room
// coordinates for this step (no grid offset yet — see spec, "non-goals"). floorPlan composes a
// list of them into the Plan the sim needs.
import type { Frame, Measure } from "./canvas"
import type { Scene } from "./draw"
import type { CatPlan, Kind, Pastime, Plan, Pt, Spot } from "./sim"
import type { Agents } from "./types"

export type TileKind = "office" | "cat-corner" | "meeting" | "lounge" | "kitchen" | "games"
export type Rect = { x: number; y: number; w: number; h: number }

export type Tile<L> = {
  kind: TileKind
  /** this tile's footprints, for the route test and the walk */
  blocks(l: L): Rect[]
  /** this tile's spots, by kind — unioned across every tile on the floor */
  spots(l: L): Partial<Record<Kind | Pastime, Spot[]>>
  /** this tile's slice of Nina's places, if it has one (only `cat-corner` does, this step) */
  cat?(l: L): Partial<CatPlan>
  /** art + furniture, at the scene's draw time */
  draw(sc: Scene, a: Agents, l: L, m: Measure): void
}

export type Home = { tiles: { kind: TileKind; at: [number, number] }[] }
```

## `kit/floor.ts` (new) — the composer

```ts
// Builds the Plan the sim needs by unioning every tile on the floor — what floorPlan() in the
// plan doc describes. For this step every tile is anchored at [0,0] (absolute coordinates); the
// grid offset in `home.tiles[].at` is read but not yet applied — step 3 applies it.
import type { Home, Tile, TileKind } from "./tiles"
import type { Plan, Pt, Spot } from "./sim"
import type { Agents, Seat } from "./types"

export function floorPlan<L extends { people: Seat[] }>(
  home: Home,
  tilesOf: Record<TileKind, Tile<L>>,
  rest: Omit<Plan<L>, "queue" | "lounge" | "oncall" | "box" | "cat"> & { cat: Pick<Plan<L>, "cat">["cat"] },
): Plan<L> & { blocks: (l: L) => Rect[] } {
  const tiles = home.tiles.map((t) => tilesOf[t.kind])
  return {
    ...rest,
    queue: [], // office tile contributes queue via its own spots() entry — see below
    lounge: tiles.flatMap((t) => t.spots as any), // placeholder — real shape built per task 3
    blocks: (l) => tiles.flatMap((t) => t.blocks(l)),
  }
}
```

This sketch is deliberately thin — task 3 below nails the exact union (which spot kinds come from
which tile's `spots()`, and how `cat-corner`'s partial `CatPlan` merges with the rest) once the
first two tiles exist to test it against. Don't take the snippet above as final; it's here to fix
the shape, not the body.

## `home.json`

```jsonc
// ~/.config/tlon/home.json default — today's office, tile for tile. TLON_HOME points elsewhere;
// re-read live like palette.json.
{ "tiles": [
  { "kind": "office", "at": [0, 0] },
  { "kind": "cat-corner", "at": [0, 0] },
  { "kind": "meeting", "at": [0, 0] },
  { "kind": "lounge", "at": [0, 0] },
  { "kind": "kitchen", "at": [0, 0] },
  { "kind": "games", "at": [0, 0] }
] }
```

Ship this as the compiled-in default (`kit/tiles.ts`'s `DEFAULT_OFFICE: Home`), the same way
`palette.json`'s absence means the compiled-in palette — no file read for this step unless a later
step (file-watch, `TLON_HOME`) asks for one. `office/kit/tiles.ts` exports `DEFAULT_OFFICE`;
nothing reads an actual `~/.config/tlon/home.json` file yet (that's wiring, not this step's check).

## The golden-frame diff (write this first)

Add to `test/wide.test.ts`, **before any extraction**, so it's red-then-green-at-every-commit:

```ts
import { createHash } from "node:crypto"

test("the room's pixels don't move: a golden hash per width", () => {
  // generated once against main (pre-cut) with `bun test -t golden --update` (see below); this
  // step's whole job is for every one of these to stay the same.
  const golden: Record<number, string> = {
    540: "<fill in from the baseline run>",
    560: "<fill in from the baseline run>",
    640: "<fill in from the baseline run>",
    696: "<fill in from the baseline run>",
    900: "<fill in from the baseline run>",
  }
  for (const [w, hash] of Object.entries(golden)) {
    const room = new WideRoom(Number(w)), a = viewOf(office(6), 1)
    for (let i = 0; i < 300; i++) room.step(a)
    const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
    const got = createHash("sha256").update(Buffer.from(fr.rgba)).digest("hex")
    expect(got).toBe(hash)
  }
})
```

**Task 0** fills in `golden` by running this against the *current* `wide.ts` (print the hash
instead of asserting, commit the filled-in table), so the test is a real tripwire from the first
extraction commit on. `Math.random` isn't seeded here on purpose — `office(6)`'s roster is enough
seats that the frame after 300 ticks is dominated by deterministic layout/furniture, not pet idling;
if a later task finds this flaky, seed it (`seeded(1, …)`) and re-capture the hashes once, not per
task.

## The route test, extended

`test/wide.test.ts`'s `"no walk crosses the furniture"` already walks every route between every
spot on the **composed** floor. Add the per-tile half the plan's check asks for: each tile's own
`blocks()` and `spots()` are internally walkable too (a tile that strands its own spot fails here
even before it's composed with the others):

```ts
test("no walk crosses the furniture, tile by tile", () => {
  for (const w of [540, 560, 700]) {
    const z = zones(w)
    for (const kind of TILE_KINDS) {
      const tile = TILES[kind](z, w)
      const l = /* same layout the composed test builds */
      const blocks = tile.blocks(l)
      const spots = Object.values(tile.spots(l)).flat()
      const inside = (x: number, y: number) => blocks.find((b) => x > b.x && x < b.x + b.w - 1 && y > b.y && y < b.y + b.h - 1)
      // a tile's own route isn't meaningful alone (routing is the composed floor's job via
      // `rest.route`) — this only checks that no spot of the tile sits inside one of its own blocks
      for (const s of spots) if (inside(s.x, s.y)) throw new Error(`${kind}@${w}: spot ${s.kind}@${s.x},${s.y} is inside its own block`)
    }
  }
})
```

## Argos → `kit/pets.ts` (new)

Moves, unchanged: the `Dog` type, the `ARGOS` dialogue object, `dogBed`/`dogBowl` (as functions of
the lounge/kitchen geometry they need — pass in the spots they anchor to, not `this.z`),
`dogDo`/`patDog`/`fussDog`/`stepDog`/`drawDog`. These become exported functions taking the `Dog`
state and whatever geometry they need as arguments (no `this`); `WideRoom` keeps a `private dog:
Dog` field (tests reach into `room.dog` directly — `test/pets.test.ts`, `test/wide.test.ts` — so
the field name and shape must not change) and calls the new functions from its own `step`/`render`.
**Stays in `WideRoom`**: `stepAntics`/`drawAntics`/`Antic` (needs both pets; it's the room's
choreography, not Argos').

## Tasks

Each is a commit. Run `mise run office:check` (or `bun test` inside `office/`) after each; the
golden-frame test and the "no walk crosses the furniture" tests must stay green from task 1 on.

1. **Golden frame, captured from today.** Add the test above with real hashes (run once, print,
   paste in). Commit alone — this is the tripwire the rest of the work proves itself against.
   *Done: `bun test test/wide.test.ts -t golden` passes against the unmodified `wide.ts`.*
2. **`kit/tiles.ts`**: the `TileKind`, `Tile<L>`, `Rect`, `Home` types above, no logic yet.
   *Done: typechecks; nothing else imports it yet, so no behavior to test.*
3. **`kit/pets.ts`**: lift Argos as described above. `wide.ts` imports from it; `WideRoom.dog`
   unchanged in shape. *Done: golden-frame + `test/pets.test.ts` + `test/wide.test.ts`'s two Argos
   furniture-collision tests all green, unchanged.*
4. **`games` tile**: cut the arcade/ping-pong/foosball/pool/aquarium furniture, spots and draw code
   into `kit/tiles/games.ts` (factory `gamesTile(z: Zones, w: number): Tile<Layout>`); `wide.ts`
   calls it instead of drawing those inline. *Done: golden-frame green; the per-tile walkability
   test passes for `games`.*
5. **`kitchen` tile**: same, for the cooler/coffee/counter/fridge. *Done: same two checks, for
   `kitchen`.*
6. **`meeting` tile**: same, for the round table/glass/oncall laptops. *Done: same, for `meeting`.*
7. **`lounge` tile**: same, for the couches/windows/plants/chat/pet/read spots (what's left of the
   lounge once kitchen and games are carved out). *Done: same, for `lounge`.*
8. **`cat-corner` tile**: same, for Nina's tower/perches/nap/litter/play/radiator and the
   `CatPlan` fragment they contribute. *Done: same, for `cat-corner`, plus
   `test/wide.test.ts`'s zoomies/antics tests (they read `plan.cat`) still green.*
9. **`office` tile**: what's left — boss desk, in-tray, beacon, crew board, manager/lead desks,
   tables, filing cabinet, server rack, the queue, `home()`. *Done: same, for `office`.*
10. **`kit/floor.ts`** + `home.json`'s `DEFAULT_OFFICE`: real `floorPlan` composing all six via
    `tilesOf`, replacing `widePlan`'s hand-built `Plan` object. `rooms/wide.ts` shrinks to the
    `WideRoom` class (render/step/the shared back-wall chrome) plus
    `export const widePlan = (w: number) => floorPlan(DEFAULT_OFFICE, TILES, restOf(w))`.
    *Done: golden-frame green at every tested width; the full composed-floor route test green;
    `mise run office:check` green end to end.*

Steps 2 and 3 (viewport, build mode) stack on this one later and are out of scope here.

## Verify

- `mise run office:check` (install, typecheck, `bun test`) — the gate for this module.
- The golden-frame test (task 1) is the "pixel-identical at every width" check the ticket names;
  the per-tile + composed walkability tests are the "every route through every block" check.
- No visual check is needed beyond these — the whole point of this step is that there is nothing
  new to look at.
