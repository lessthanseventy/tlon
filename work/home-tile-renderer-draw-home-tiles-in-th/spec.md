# Spec — home-tile renderer (ticket #45, thread 187)

## Goal
Build mode draws the home as pixel art, not `LI`/`KI` two-letter codes, through a tile-kind → sprite
hook that later work (garden #176, mailbox street tile #185, weather #172, #40) plugs into.

## Today
`kit/home.ts` is the engine (grid, place/drop/rotate/undo); `tui/main.ts` `case "build"` renders each
cell as a text row `" XX "`. Kinds: living, kitchen, bathroom, bedroom, street. No pixels.

## Design
- **`kit/homeart.ts`** (new, shared kit; no Cairo/terminal imports):
  - `type TileArt = (c: Canvas, x: number, y: number, tile: HomeTile) => void` — paints one tile into
    a `TILE`×`TILE` px square at (x,y), honouring `tile.rot` via a small `rotated(rows, rot)` sprite helper.
  - `export const TILE_ART: Partial<Record<string, TileArt>>` — the hook. Registering a kind = adding a
    key (+ sprite). Unregistered kinds fall back to `plainTile` (flat ROLE-coloured square + kind
    initial in `font.ts`), so adding a catalogue kind never breaks drawing.
  - `renderHome(home, cursor, carrying, refused, win): Frame` — iterates `gridWindow`, paints every
    cell (empty = dim grid cell), cursor bracket via `Ink brackets` (alarm role when refused),
    carried tile ghosted at the cursor. Colours are `ROLE`s only.
  - Art this step: living, kitchen, bathroom, bedroom, street (simple 12–16px sprites). Garden/mailbox/
    weather are NOT drawn here — they register in their own tickets.
- **`tui/main.ts` build case:** the room image area shows `renderHome(...)` while `mode.kind === "build"`
  (reuse the existing frame/kitty/half-block path; set `roomChanged` on each mutation); the pane keeps
  the action list but drops the text grid rows. `Hit`s per cell make tiles clickable-to-move-cursor.
- Out of scope: mailbox, weather, errands, garden art, desktop surface, any server change.

## Tasks (each one commit, TDD)
1. `rotated()` sprite helper + test (4 rotations of an asymmetric 3×3 round-trip).
2. `TILE_ART` registry + `plainTile` fallback + test (unknown kind draws non-empty; registering a stub
   kind is called with the tile).
3. Per-kind sprites (5) + test (each kind's pixels differ; rot 90 differs from rot 0 for an asymmetric kind).
4. `renderHome` + test (frame size from `gridWindow`; cursor ink alarm when refused; carried ghost).
5. Wire into `tui/main.ts` build mode + `mise run office:golden` unchanged (wide room untouched) + WCAG
   test still green (no new text labels below 4.5:1).
6. Drive with `drive-office` skill: enter `B`, place/rotate/cycle, screenshot; note in review so #185/#172/#176 are released.

## Verify
`mise run office:check`, `mise run check`, plus the drive-office run.

## Open question (for the operator)
Build mode currently has no room image of its own. Assumed: **swap the room image for the home render
while building** (Esc returns). Alternative: draw the home as a small preview in the pane beside the text grid.
