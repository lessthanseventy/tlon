# A home beside the office — the dollhouse, the life quests, and a room that scrolls — design

**Date:** 2026-10-06
**Status:** agreed with Andrew (the calls in §9), nothing built. Three tracks in §8, each step gated by a check.
**Asked:** Andrew: *"an alternative space … to manage more of my life and less of a dev shop. like
where my sim clocks out … use the primitives we've managed to come up with to gamify my life. down
to like leveling up when i brush my teeth … a scrollable office so it doesn't have to feel so
cramped … predefined sprites, a character editor/importer, "rooms" that you could pick up and place
to customize your own home and office. people play the sims just to build their dollhouse and play
dollies … more character models, more pets, config screens for their behavior (is nina sassy or dumb
or playful) … literally as much whimsy as we can find."*

---

## 0 · The call

Four pieces, in the order they unlock each other:

1. **A floor is tiles.** A room stops being one hand-placed floorplan (`rooms/wide.ts`, 1037 lines
   of constants) and becomes rooms you place on a grid, each a self-contained module with its own
   furniture, spots and pet places. The office you have today is one arrangement of tiles; a home is
   another; both live on one floor with a street between them. The sim already walks a `Plan`
   (`kit/sim.ts`); the plan becomes composed instead of written.
2. **The floor scrolls.** The TUI stops shrinking the world to the terminal and shows a viewport
   over a floor as big as you build, following your figure, panning on keys and the mouse. This is
   what makes "a little more wild with the design" affordable: nothing has to fit in 540×200.
3. **Life has quests.** The server gets the two rows the life side is missing — a **routine** (brush
   your teeth, nightly) and a **quest** (one-off, "book the dentist") that *you* complete — and XP,
   level and streaks as **derived views over the done-stamps**, never stored. The calendar, alerts
   and schedules you already have carry the rest (meetings alarm, a scheduled agent can nag).
4. **Dollies.** Predefined looks, a pixel editor and a PNG importer for your own figure and the
   coworkers'; more pets, each with a **temperament** you set on a card (sassy ↔ sweet, sharp ↔
   dim, playful ↔ lazy) that reweights what they do and what they say. Whimsy is a list (§7)
   and it is meant to keep growing.

What this is *not*: a second server, a second app, or a game loop that runs when you are not
looking. It is the same brain, the same TUI, the same `Frame` contract — one more kind of workspace
and a room that is built instead of drawn.

It is a lot for one plan, and that is fine: it is **one design with three independent tracks**
(the floor, the life side, the dollies — §8), each shippable alone, so it can be three worklines
at once without any of them waiting on the others. Everything the operator configures lives in
files under `~/.config/tlon/` and is **re-read live** (the palette's file-watch pattern), so no
change here, from moving a wall to making Nina sassy, ever needs a restart.

## 1 · What exists, and what each piece reuses

| Exists | Where | Reused as |
|---|---|---|
| Snapshot shape, `GET /api/office` | `Server.Office.status`, `office/kit/types.ts` | grows a `life` block (§3.4); no second feed |
| `Frame` / `Canvas` / `Ink` / `Hit` | `kit/canvas.ts` | unchanged; the floor renders to one bigger `Frame` |
| Sprites as char rows + a role map | `kit/sprites.ts` | the import/export format for the editor (§5.1) |
| `Plan<L>`, `Sim`, `Pastime`, `CatPlan` | `kit/sim.ts` | a tile exports a *local* plan; the floor composes them (§2.2) |
| Furniture shared by rooms | `kit/furniture.ts` | the first tile kinds are cut from here and `wide.ts` |
| Nina's lines | `kit/voices.ts` | becomes one voice *pack*, picked by temperament (§5.3) |
| Argos | inline in `rooms/wide.ts` | lifted to `kit/pets.ts` as the second species |
| TV channels | `kit/tv.ts` | a `tv` tile; the home gets its own channels |
| Palette roles, live `palette.json` | `kit/palette.ts`, `tui/main.ts` | the same file-watch pattern serves `home.json`, `looks.json`, `pets.json` |
| `Server.Schedule` (agent / workline / script, cron or `at`) | `server/lib/server/schedule.ex` | a routine's nag is a schedule; a routine is **not** a schedule (§3.1) |
| `Server.Calendar` + `Server.Alerts` (uncommitted, this tree) | `calendar.ex`, `alerts.ex` | meetings on the home wall calendar; a due routine is one more alert level |
| `Server.Event` (closed kinds, outcomes with no other home) | `event.ex` | **not** for XP — a done routine has a home, its own row (§3.2) |
| `Server.Note`, `Server.Fact` | | the fridge door (notes scoped `workspace`); "stated" facts about you stay facts |

## 2 · The floor: tiles, not a floorplan

### 2.1 What a tile is

A **tile** is a room module: a fixed size in logical px (a 60×60 "cell" grid — the office's current
zones are 2×3 and 3×3 of these), its art, its furniture, and the spots the sim needs, all in
*tile-local* coordinates:

```ts
// kit/tiles.ts
export type TileKind = "office" | "meeting" | "lounge" | "kitchen" | "cat-corner" | "games"
  | "bedroom" | "bathroom" | "living" | "gym" | "garden" | "street" | "hall"
export type Tile = {
  kind: TileKind; w: number; h: number                       // in cells
  draw(sc: Scene, a: Agents, m: Measure, o: Pt): void        // art + furniture at origin o
  blocks: Rect[]                                             // footprints, local
  spots: Partial<Record<Kind | Pastime, Spot[]>>             // desk, queue, lounge, oncall, pastimes…
  cat?: Partial<CatPlan>                                     // nap, perch, litter, warm… (local)
  doors: ("n" | "s" | "e" | "w")[]                           // which edges open
  hits?(a: Agents, o: Pt): Hit[]                             // what you can click here
}
```

A **floor** is tiles placed on the cell grid, plus which ones are the office and which the home:

```jsonc
// ~/.config/tlon/home.json — yours, like palette.json; TLON_HOME to point elsewhere; re-read live
{ "tiles": [
  { "kind": "office",  "at": [0, 0] }, { "kind": "meeting", "at": [2, 0] },
  { "kind": "lounge",  "at": [4, 0] }, { "kind": "cat-corner", "at": [0, 2] },
  { "kind": "street",  "at": [0, 3], "w": 6 },
  { "kind": "living",  "at": [0, 4] }, { "kind": "kitchen", "at": [2, 4] }, { "kind": "bathroom", "at": [4, 4] },
  { "kind": "bedroom", "at": [0, 6] }, { "kind": "gym", "at": [2, 6] }, { "kind": "garden", "at": [4, 6] }
] }
```

The default `home.json` *is today's office*, tile for tile, so the day the floor lands nothing
looks different until you move a wall. The file is the surface's (law: "a room is a surface's
own") — it is not server state, exactly as the palette is not.

### 2.2 Composing the plan

`floorPlan(home): Plan<Layout> & { blocks }` builds what `widePlan` builds today, by union:

- `home(agent)` — the first `desk` spot in any `office` tile that has a free seat; the queue,
  lounge, oncall, box, pen, exit spots are the concatenation of every tile's, offset by its origin.
- `route(x, from, goal)` — tile-local routing (a tile's own aisle rows, as `wide.ts` does with
  `laneOf`) joined by a **door graph**: BFS over tiles through their open edges, waypoint at each
  door's midpoint. `CatPlan.door(from, to)` already has this shape; it becomes the one router for
  cats and people.
- `blocks` — every tile's footprints, offset. **The existing test holds**: `test/wide.test.ts`
  walks every route between every spot through every block; it runs over the composed floor and
  over each tile alone. A tile that strands a spot fails here.
- `cat` — Nina picks her nap/perch/warm from whichever tiles offer one; a pet with no `cat-corner`
  on the floor sleeps on a couch.

`rooms/wide.ts` becomes the first set of tile definitions plus a one-line `widePlan = floorPlan(DEFAULT_OFFICE)`.
`rooms/rail.ts` stays as it is (the desktop's rail is 144 wide and hand-fit; it gains nothing).

### 2.3 Picking up and placing

In the TUI, `b` (build) enters **build mode**: the floor dims, a cursor the size of one cell moves
on the arrows, `⏎` picks up the tile under it, arrows carry it, `⏎` drops it (refused — red flash
and the cursor stays — where it would overlap or cut the last door between two halves), `n` cycles
a new tile kind from the catalogue onto the cursor, `x` removes, `r` rotates a tile whose doors
allow it, `esc` leaves. Every drop writes `home.json`; the live file-watch repaints. Undo is the
file's history: build mode keeps the last ten writes in memory and `u` steps back.

Build mode is the dollhouse. It is also the first thing to put in front of Andrew, because the
tile catalogue's quality is what decides whether this feels like Sims or like a config file.

## 3 · The life side: routines, quests, XP

### 3.1 Two rows, not one

The server has nothing today that *the operator* completes. `Server.Schedule` fires machines;
`Server.Todo` is thread-scoped plan steps; `Server.Habit` is a working preference. So, two new
rows, both owned by a workspace whose `kind` is `home` (§3.3):

```
routine          -- recurring, yours: "brush teeth", "stretch", "water the plants"
  id, workspace_id, title, every (cron or @daily/@weekly), window_minutes (how long after
  `every` it still counts as on time), xp (integer, default 10), tile (the room it belongs to:
  "bathroom"), enabled, created_at
routine_run      -- one completion; the ONLY thing that is written when you do the thing
  id, routine_id, due_at, done_at, late (bool, computed at the stamp)
quest            -- one-off: "book the dentist", "fix the bike", due optional
  id, workspace_id, title, due_at, xp, done_at, created_at
```

A nag is **not** a column: a routine that should remind you gets a `Server.Schedule` of kind
`agent` whose body is "ask Andrew whether he's done X" — the coworker machinery you already have,
standing thread, posted in the home workspace's lobby. The two are linked by convention (the
schedule's `title`), not by a foreign key; the first time the link bites, add the key.

### 3.2 XP, level, streak are views

Spec §2 (one source) decides this: there is no `xp` column on anything, no `level` row, nothing
to drift. `Server.Life` computes, per workspace:

- `xp` = Σ `routine.xp` over `routine_run` where `done_at` is set and not `late`, plus half for
  late ones, plus Σ `quest.xp` over done quests;
- `level` = `floor(sqrt(xp / 100))` (a curve that is quick at first and slows — tune on taste;
  it is one function);
- `streak(routine)` = the run of consecutive dues with a `done_at`, counted back from now;
- `due` = every routine whose current due is unmet, with how long is left in its window.

A completion that would change the level returns `{level_up: true}` from the write, and the
office throws the same party `wide.ts` throws when a thread ships (`Party` in `sim.ts`) — only now
it is your figure in the bathroom tile, with the cat.

Nothing is written to `Server.Event`: a done routine has a home (its run row). The `cited` /
`work_landed` kinds are outcomes of agent work and stay that.

### 3.3 Where it lives: a `home` workspace

A workspace gets a `kind` (`office` by default, `home` for this). It is the smallest change that
gives the life side a scope: routines, quests and the fridge notes hang off it, coworkers can be
employed by it (a planner who writes the week's quests from your calendar; a nag), its lobby is
where the nags land, the needs queue and alerts work unchanged. `Server.Workspaces.create` takes
the kind; the TUI's workspace switch (today's `w`) shows it with a house instead of a building.

Clocking out is then literal: the office tiles are one workspace's rooms, the home tiles another's,
and **your figure walks from the one to the other**. Four things move you, and all four are in:

- **the clock** — `home.json`: `"clock_out": "18:00"`, `"clock_in": "09:00"`; at the time your
  figure sets off and the viewport follows the walk;
- **the keys** — `h` (home) and `o` (office): the viewport jumps and your figure fast-walks across,
  the easy go-between;
- **what you are doing** — opening a thread, a terminal or lazygit walks you to the office;
  stamping a routine or opening the life card walks you home. The room follows your attention, and
  the clock and keys only override it;
- **coworkers cross too** — a consult (`Visit`) or a nag walks its coworker over the street to the
  home door and rings (§7, the doorbell); otherwise they stay on their side.

While you are home, the office still runs — coworkers at desks, the queue at your door — you just
watch it from across the street, and the needs count in the header is the same count.

### 3.4 On the wire

Operator-API routes, all under `/api/life` so they read as one thing:

```
GET    /api/life                      {xp, level, next_level_at, streaks, due, quests, today}
POST   /api/life/routines             {title, every, window_minutes?, xp?, tile?}
PATCH  /api/life/routines/:id
POST   /api/life/routines/:id/done    → {run, level_up}
POST   /api/life/quests               {title, due_at?, xp?}
POST   /api/life/quests/:id/done
```

The office snapshot carries the summary (`life: {level, xp, due: [...]}`) so the room draws it
without a second fetch; the detail pane reads `/api/life` when you open the card. Both are
`Server.Office` context functions first, routes second, per the office's law.

MCP: the same six as tools for a coworker in the home workspace (`life_status`,
`routine_done`, …) so "I brushed my teeth" said to a coworker lands the stamp. The MCP adapter
already maps operator-API routes to tools; nothing new in the adapter.

### 3.5 Four doors to one stamp

Every way of saying "done" lands the same `routine_run` row through the same `Server.Life`
function; the surfaces differ, the write does not:

1. **the room** — a due routine glows in its tile; click it, or walk your figure there and `⏎`;
2. **the life card** (`L` in the TUI) — due and upcoming listed, keys to add, edit and stamp; the
   only door for a routine with no tile, and where routines and quests are *created*;
3. **a coworker** — "I brushed my teeth" to a home-workspace coworker calls `routine_done` over
   MCP; a planner coworker writes the week's quests from the `.ics` feed and the fridge;
4. **a nag** — a `Server.Schedule` of kind `agent` asks at the time; its dialog is a need
   (`Server.Attention`), so it shows in the needs queue and as a `decision` alert, and answering
   it stamps the run.

### 3.6 In the room

- The **routine lives in its tile**: brush teeth is a glint on the bathroom sink; stretch is the
  gym mat; water the plants is each plant. A due one *pulses* (the `glow` the canvas already has,
  on a 2-second sine). A late one has the cat sitting on it.
- The **fridge door** (kitchen tile) is `Server.Note` scoped to the home workspace: shopping
  lists, whatever. Same note the agents can read and write.
- The **wall calendar** moves from the office back wall to the living-room tile for the home
  side, drawn from the same `calendar` days plus the `.ics` meetings (`Server.Calendar`) as dots
  with a time.
- **XP bar** in the header beside the needs flag: `lv 7 ▰▰▰▱▱ · 3 due`. Level-ups also go on the
  corkboard as a `CorkNote` from the cat.
- A **trophy shelf** tile: one trophy per streak milestone (7, 30, 100) and per level, drawn from
  the view, never stored.

## 4 · The floor scrolls

Today `layoutScreen` picks the largest whole scale ≥2 at which the whole room fits the terminal,
else falls back to the rail. The floor has no "fits". Instead:

- The floor renders to a `Frame` of its full size (a 6×8-cell floor at 60 px cells is 360×480 at
  1x). The scale is picked for *legibility* (the type scale's rule stays: `min(round(cell.h/18),
  floor(k/2))`), at 2 or 3, never for fit.
- A **viewport** in `tui/paint.ts`: `{x, y, w, h}` in logical px, following your figure with a
  dead zone (it pans when you are within a cell of an edge), `shift+arrows` and mouse-drag pan,
  `.` recentres on you, `,` on whatever is waiting on you.
- **kitty mode**: the whole floor's PNG goes to the terminal **once** per frame change and the
  viewport is a *placement* with a source rectangle (`a=p` with `x=,y=,w=,h=`): panning re-places,
  it never re-encodes. The frame cadence is what it is today.
- **half-block mode**: the viewport crops rows before conversion. Half blocks already cost one
  cell per 2 px, so a big floor is fine.
- `Ink` and `Hit` are clipped to the viewport at paint time; a balloon for someone off-screen
  becomes an edge marker (`◂ Argos`), the needs queue's "you - N waiting" call-out stays pinned
  to the header, never to the floor.
- `test/wcag.test.ts` runs its label checks on *every* viewport position a floor can take (the
  set is small: it steps by a cell), so a label legible in one corner is legible in all.

The rail is untouched; a terminal under `WIDE_MIN_W` still gets it.

## 5 · Dollies

### 5.1 Looks: predefined, drawn, imported

A **look** is what `sprites.ts` already hashes from a name (`hair`, `hairRole`, `decor`, `fav`,
`emote`, `slow`, `blink`) plus a body set. `~/.config/tlon/looks.json` pins looks by agent name
and holds custom sprites; absent, the hash rules as today, so nobody changes overnight.

- **Predefined**: the five hairs become a catalogue of parts — hair (12), skin tone (6 roles, so
  WCAG and themes hold), outfit (10: hoodie, suit, apron, gym, pyjamas, lab coat, …), accessory (8:
  glasses, headphones, hat, …). Parts are row overlays exactly like archetype `GEAR` is now. A
  card in the TUI (`l` on a person, or on yourself) cycles each part with the arrows and shows the
  four views; `⏎` saves to `looks.json`.
- **Editor**: the same card, `e`: a 12×22 grid, arrows move, letters paint a role (the role
  legend is the palette's, so a drawn sprite re-themes like everything else), four views as four
  tabs, mirroring on for the side views by default. Saves char rows into `looks.json` — the format
  is the one `sprites.ts` reads; no conversion.
- **Importer**: `tlon office import-sprite me.png` (and drag-drop is a later idea): a 12×22 (or
  whole-sheet 48×22) PNG, each pixel snapped to the nearest palette **role** by Lab distance,
  transparent → `.`. The output is printed as char rows and written to `looks.json`. Anything the
  Aseprite crowd makes drops straight in. Over 12×22 refuses with the size; we do not scale.
- The office-side coworkers keep their archetype gear on top of any look (the hard hat says what
  they are; the look says who).

### 5.2 Pets: species, and more of them

`kit/pets.ts` lifts Nina (`sim.ts` cat machinery + `voices.ts`) and Argos (inline in `wide.ts`)
behind one interface:

```ts
export type Species = "cat" | "dog" | "bird" | "rabbit" | "fish" | "duck" | "snake" | "capybara"
export type Pet = { name: string; species: Species; look: PetLook; temperament: Temperament; home: TileKind }
```

A species is: a sprite set (4 views × a few frames), the **modes** it has (`sit`, `sleep`, `play`,
`zoom`, `perch`, `swim`, `follow`, `beg`, `fetch`), the places it wants from a tile's `cat`-style
offer, and a voice pack. Fish live in the tank tile and never leave it; the duck follows you between
tiles; the capybara is slow, sits in the garden pond, and every other pet comes to sit with it (that
is the joke, and it is true to life). `~/.config/tlon/pets.json` lists them; the default is Nina
and Argos as they are.

### 5.3 Temperament: the mini character creator

Each pet (and, later, each coworker's banter) has three axes, each −2..2:

| Axis | Low | High | What it moves |
|---|---|---|---|
| **warmth** | sassy | sweet | the voice pack's line weights (teasing ↔ encouraging), how often it comes to you (`byYou`) |
| **wits** | dim | sharp | whether it "notices" a due routine (sits on the sink) or just naps; wrong-room wandering; how pointed its corkboard lines are |
| **energy** | lazy | playful | the mode table's weights (`sleep` ↔ `zoom`/`play`), stroll radius, how often it starts a `fuss` |

The card (`p` on a pet): the pet's four views, the name (the editor's text input), species cycle,
the three axes as five-dot rows moved by the arrows, and a **live preview** — the pet acts out
the setting on the card for a few seconds (a lazy, sassy Nina yawns and says something cutting).
`⏎` saves to `pets.json`. The voice packs are what `voices.ts` is now, split into
`{sassy, sweet, dim, sharp, lazy, playful}` buckets and weighted by the axes.

Coworkers get the same three axes under their card later (the banter kinds in
`Server.Office.Banter` are already weighted; the axes become the weights). That is server-side
policy (a coworker's personality travels with the workspace), so it goes in the coworker row, not
a file — a later step, flagged so the file/row line stays sharp.

## 6 · Nothing starts empty — presets, overrides on top

Andrew: *"I get empty page syndrome … bake in as many prebuilt options as possible. sane
configurable overridable defaults."* So the rule for every file in `~/.config/tlon/`:

- **Absent is a named preset, not empty.** No file → the default preset. Every surface that reads
  a file ships with a catalogue of presets compiled in, and the first thing each card shows is
  the catalogue, not a blank.
- **A file is a preset plus overrides.** `{ "preset": "studio", … }` — only what you changed is
  written; the rest keeps following the preset as the catalogue improves. The build/look/pet cards
  write files this way, so a file you never hand-edit never pins a stale copy of a default.
- **Any preset can be forked**: `f` on a card copies it as a full file to edit freely.

The catalogues, each a first-class list in the kit with a preview in its card:

| What | Presets shipped at step | Examples |
|---|---|---|
| **Floors** (`home.json`) | 3 | `office` (today's room, the default), `studio` (office + a one-room flat), `house` (office, street, a 2×2 home with garden), `loft`, `cabin` (no office: the all-home floor for a weekend), `campus` (two offices, two homes: a floor for two tlons) |
| **Tiles** | 1, 3 | the office six; `living`, `kitchen`, `bathroom`, `bedroom`, `gym`, `garden`, `street`, `hall`, `pond`, `balcony`, `workshop`, `music-corner`, `trophy-shelf`, `tank` |
| **Looks** (`looks.json`) | 6 | 24 ready figures by name (`"me": "hoodie-mop"`), the parts catalogue behind them (12 hair × 6 tones × 10 outfits × 8 accessories), and the hash as the default for anyone unnamed |
| **Pets** (`pets.json`) | 7 | `nina-and-argos` (the default), `cat-only`, `menagerie` (one of each species), `pond-life` (fish, duck, capybara), `none`— step 7 ships `nina-and-argos` and the cat slot's species (cat, rabbit, bird); the rest wait on a pet array and the tank/pond tiles |
| **Temperaments** | 7 | `classic nina` (sassy, sharp, playful), `menace`, `golden retriever` (sweet, dim, playful), `old cat` (sweet, sharp, lazy), `gremlin`, `zen` — picked by name on the card, then nudged by axis |
| **Routine packs** (server, `POST /api/life/packs/:name`) | 4 | `morning` (teeth, water, stretch, make the bed), `evening` (teeth, dishes, in bed by), `weekly home` (plants, laundry, bins), `desk body` (stand, eyes off screen, walk), `pet care` (feed, litter) — each a set of routines with tile, window and xp filled in, editable after |
| **Voice packs** | 7 | per species and per temperament bucket, so a new pet has lines on day one |

A preset is also what a coworker reaches for: "set up a home" in the home workspace's lobby
applies `house`, `morning` + `evening`, and `nina-and-argos`, and says what it did.

## 7 · Whimsy — the list that keeps growing

Each is one afternoon or less once §2 and §5 are in; none needs a design.

- Weather comes inside: rain on the garden tile, snow piling on the fence, the cat by the
  radiator (already) and the dog refusing to go out.
- Day and night: the floor's light follows the real clock; lamps come on tile by tile; a pet
  asleep at night, you in pyjamas after clock-out.
- Birthdays and anniversaries from the `.ics` feed: bunting on the living-room tile, a cake on
  the kitchen counter, the coworkers crowd in.
- A streak milestone frames a photo on the wall; a lost streak takes it down (the trophy shelf's
  honest cousin).
- Level-up fanfare: the party, plus the TV switching to a "channel" that shows your level in the
  tlon font.
- A mailbox on the street tile: the needs queue as letters; a coworker walks one over.
- A doorbell: a consult visit (`Visit`) from the office rings at the home door; you can let them in
  or not.
- Seasons on the garden: planting a quest, harvesting on its done date.
- A music corner: whatever `playerctl` says is playing scrolls on the stereo; the pets dance to
  anything over 120 bpm (if the player says).
- The gym tile reads a routine's streak into dumbbell size.
- Argos fetches the newspaper (the morning brief as a note) and drops it at your feet.
- Sleep: a `bedroom` routine ("in bed by 23:00") — your figure lies down when it is stamped;
  late, the cat is already on the bed.
- Visitors: another tlon on another machine (the cohesion model) can send a figure over the
  street — its roster entry walks in, says hi, leaves. The smallest multiplayer.

## 8 · Three tracks, each step gated

Every step is a PR on `main` (rebase, stack where one builds on the last), green `mise run check`,
and a check of its own named here. The three tracks touch different code and **run in parallel**
as three worklines; within a track the steps stack. The two joins are named.

- **Floor** (office kit + TUI): steps 1 → 2 → 3.
- **Life** (server, then its room): steps 4 → 5; step 5 joins the Floor after 3 (it needs home
  tiles to put routines in) and ships the life card and header first, which need no tiles.
- **Dollies** (sprites, pets): steps 6 → 7; step 7 joins the Floor after 1 (Argos lifts out of
  `wide.ts` as it is cut into tiles, so the lift is step 1's, and step 7 builds on it).

| # | Step | Check |
|---|---|---|
| 1 | **Tiles under the office** — `kit/tiles.ts`, `floorPlan`, `wide.ts` cut into tile defs, default `home.json` = today's office | the room renders pixel-identical to today at every width (`test/wide.test.ts` gains a golden-frame diff); every-route-through-every-block holds on the composed floor and on each tile alone |
| 2 | **Viewport** — the floor at a legibility scale, kitty placement crop, half-block crop, follow + pan keys | `wcag.test.ts` on every viewport position; `drive-office`: pan to each corner, read the header back |
| 3 | **Build mode** — place, pick up, rotate, remove, undo; writes `home.json`; the first home tiles (living, kitchen, bathroom, bedroom, street) | a driven session builds a 2×2 home and the file matches; a drop that cuts the floor in two is refused |
| 4 | **`home` workspace + routines/quests/XP** — migration, `Server.Life`, routes, MCP tools, snapshot `life` block | `menard run test --in server`: level from runs, streak with a gap, late within/outside window, level_up on the crossing stamp; `check:names` for the new routes |
| 5 | **The life room** — routines in their tiles, pulse/stamp, fridge notes, calendar on the wall, XP in the header, clock-in/out walk | a driven session stamps a due routine from the room and `/api/life` shows it; the walk is seen, not assumed |
| 6 | **Looks** — parts catalogue, the look card, the editor, `import-sprite`, `looks.json` | a round trip: import a PNG → `looks.json` → draw → the pixels match the PNG's role-snapped version; WCAG on every skin tone against every tile floor |
| 7 | **Pets + temperament** — `kit/pets.ts`, two new species, `pets.json`, the pet card with live preview | per-axis: mode-table weights move the way the table says (a unit test over 10k ticks); the card's preview is driven and read back |
| 8 | **Whimsy** — from §7, one each, as they appeal | each its own one-line check in its PR |

Step 1 ships with `wide.ts` cut into tiles and Argos in `kit/pets.ts`; step 4 and step 6 can open
the same day, on nothing.

## 9 · Decided (2026-10-06)

- **One floor, with the go-between of two.** Office and home across a street on one map, *and*
  `h`/`o` jump you across instantly — the scrolling world and the quick switch, not one or the
  other (§3.3). If the first build feels like too much map, the street tile gets shorter, not cut.
- **Files, live.** `home.json`, `looks.json`, `pets.json` beside `palette.json`, re-read within a
  second of a change like the palette is. Nothing rendering-side goes in Postgres; the one later
  exception is a coworker's temperament (§5.3), which is workspace policy and goes on its row.
- **All three tracks start together** (§8), as three worklines.
- **Every door to a stamp is in** (§3.5): the room, the card, a coworker, a nag.
- **Every way home is in** (§3.3): the clock, the keys, what you are doing, and coworkers cross.
- **The life side is a workspace of kind `home`**, not machine-wide rows.
- **After the plan: the doc only.** Committed on its own branch as a PR; worklines open when
  Andrew says.

## 10 · Still open, settled by looking

- **Cell size.** 60 px makes today's office 2×3 and 3×3 tiles; 40 gives finer placement but the
  meeting room becomes an odd 2×2.5. Pick after the first tile cut, by looking.
- **The XP curve and the numbers** are placeholders. Every value is one function; tune by play.
- **Privacy of the life side on the server**: routines and quests are plain rows in the same
  Postgres as the dev work, readable by any coworker with the `home` workspace's MCP tools. Fine
  on this box; the README names it before anyone else runs a `home` workspace (step 4's PR).
- **"Stated about me" stays a fact.** Facts with provenance `stated` already hold "Andrew said";
  the life side grows no parallel memory, and a home coworker banks facts the same way. Step 4
  holds to this unless it bites.
