# Floor step 2: the viewport scrolls — spec

Ticket #20, §4 + §8 step 2 of `docs/plans/2026-10-06-home-space-and-dollhouse-design.md`.
Scope: **office/tui only** — the viewport and panning over the existing wide room. Not in scope:
build mode (step 3), home tiles, life/routines, dollies (steps 4–8). The room stays today's
office; only how it's *shown* changes.

## Decided with Andrew (2026-10-07)

1. **Legibility scale.** Kitty mode: flat `k = 2`, never derived from fit. Half-block mode keeps
   today's fit-based `k` — a half-block cell is already the smallest unit, so there's nothing
   finer to fall back to.
2. **Pan keys.**
   - `shift+Up/Down/Left/Right` — pan by one `k`-scaled grid cell per keypress. Terminal
     key-repeat on a held key drives continuous pan; no separate repeat/continuous-scroll logic.
   - mouse click-drag — pans 1:1 with drag distance, in logical px.
   - `.` — recentre the viewport on your position, and (re)enter follow mode.
   - `,` — recentre on whoever is in the needs queue.
   - Panning clamps at the floor's edges: the viewport can never show past `{0,0}`..`{floorW,
     floorH}`.
3. **Follow vs. manual pan.** Any manual pan (shift+arrows or drag) turns follow off until `.` is
   pressed again. The viewport then stays exactly where you left it.

## One clarification this spec adds (flag if it's not what you meant)

Step 2 is office-only — there is no "your figure" walking the floor yet (`kit/sim.ts` places only
coworkers and pets; "your office" in `rooms/wide.ts` — `OFF_W`/`OFF_LANE`/`OFF_DOOR` — is a static
zone, not a moving actor; an operator figure is life/home scope, steps 4–5). So for step 2:

- **`.` centres on your office zone** (the existing static area), not a moving figure.
- **`,` centres on the first needs-queue item's location**: resolve `Need.thread_id` →
  the roster entry's `agent` → that agent's current spot on the floor (needs a new `Sim.at(agent):
  Spot | null` accessor — none exists today). Blocking items first, then to-decide; an empty queue
  is a no-op (stay put, no beep).
- Follow mode (`.`) therefore always points at the same fixed zone in step 2; it stops being a
  no-op once step 4/5 give you a moving figure. No step-2 code should assume the followed target
  moves.

## Geometry

- `Viewport = { x: number; y: number; w: number; h: number }`, in logical px — the same space as
  `Frame.rgba`/`Ink`/`Hit`.
- `office/tui/paint.ts`'s `Geometry` gains the floor's full logical size (`floorW`, `floorH`),
  distinct from the viewport's cell box (`cols`, `rows`), since the floor can now exceed the
  terminal.
- Kitty mode: `kittyImage` still encodes the **whole floor's PNG once per frame change**; the
  viewport is a placement **source rectangle** (`x=,y=,w=,h=` on the `_Ga=p` placement command),
  not a re-encode. Panning only changes the placement's source rect.
- Half-block mode: `textLayer` crops its row/col loop to the viewport's range before converting —
  no scale change, just a different window into the same 1x art.
- `Ink`/`Hit` clipping: anything (text, brackets, balloon, click target) outside the viewport is
  dropped from `Hit`s (nothing to click there) and, for a balloon/label, replaced by a one-glyph
  edge marker (`◂ Name`) pointing off-screen in the direction it fell. The needs-queue header
  call-out (`⚑ N blocking · M to decide`, `main.ts:908-914`) is unaffected — it's already in the
  header row, never on the floor.

## Check (from the ticket)

- `office/test/wcag.test.ts` runs its label-contrast checks at every viewport position a floor can
  take (steps by one cell — the set stays small for today's office-sized floor).
- `drive-office`: pan to each of the four corners, read the header back to confirm position (the
  header gets a small debug readout of the viewport's current `{x,y}` for this to assert against —
  see task 5 below).

## Files touched

- `office/tui/term.ts` — shift+arrow key mapping.
- `office/tui/paint.ts` — `Geometry` gains `floorW`/`floorH`; `geometry()` legibility branch;
  `kittyImage`/`textLayer` take a `Viewport` and crop.
- `office/tui/viewport.ts` *(new)* — `Viewport` type, clamp, pan, and the follow/`,` target
  resolution.
- `office/kit/sim.ts` — `Sim.at(agent)` accessor.
- `office/tui/main.ts` — viewport state, `onKey` cases, `onMouse` drag-pan, header debug readout.
- `office/test/wcag.test.ts`, `office/test/viewport.test.ts` *(new)*.
