# office — the pixel-art room over the server

The office is the server's state as a room: coworkers at desks when they work, in the lounge when
idle, queued at your door when a thread waits on you; the whiteboard holds the worklines, the crew
board who is on what; Nina, your cat, keeps you company. TypeScript on bun, no runtime deps.

- `kit/` — what every office surface shares: the snapshot's types (`types.ts`, the shape of
  `Server.Office.status`, served at `GET /api/office`), the data views (`crew.ts`: a workspace's view, the crew, the
  whiteboard's columns), sprites and looks (`sprites.ts`), the colour roles (`palette.ts`), the
  1x canvas and the **frame** a room hands a surface (`canvas.ts`), a bitmap font (`font.ts`).
- `rooms/` — rooms built from the kit. `rail.ts` is the desktop's right-rail room, and the TUI's.
- `tui/` — the standalone terminal app (`mise run office:run`), Linux and macOS; `mise run
  office:build` compiles it to one self-contained executable per platform (`office/dist/`).

## Law

- **A room renders to a `Frame`, never to a toolkit.** Art into a 1x RGBA canvas; text, brackets
  and balloons as `Ink` in logical pixels; clicks as `Hit`s. Each surface paints the frame its own
  way (the desktop with Cairo, the TUI as a kitty image or half blocks) and measures its own text
  (`Measure`). A Cairo, Gdk or terminal import under `kit/` or `rooms/` breaks every other surface.
- **Shared means the kit; a room is a surface's own.** Sprites, looks, data views and the frame are
  shared; floorplans, furniture and spots belong to their room, so a bigger room can differ freely.
  Lift room code into the kit when a second room needs it, not before.
- **Every colour is a `ROLE`, read at draw time.** A themed surface hands its roles in with
  `useRoles`; shades between roles come from `tint`, never a literal.
- **The TUI talks to the server only over the operator API** (`/api/*` on the service's loopback
  port, `TLON_URL` to point elsewhere; `tui/data.ts`). Its read models are `Server.Office`, the same
  function `tlon-cli.sh shell-status` serves the desktop — a new read is a context function and a
  route first, never a query in the client. That is what lets a compiled TUI run with no checkout.

## Gotchas

- **ghostty (1.3 tip) segfaults inflating some zlib-compressed kitty images (`o=z`)** — bun's own
  deflate output among them. The TUI sends PNG (`f=100`, `tui/png.ts`); don't "optimise" back to `o=z`.
- **Terminal text snaps to cells**, too coarse for the room's labels (rows 4.5 logical px apart
  collide). In kitty mode the ink is drawn into the image with `kit/font.ts`; half-block mode keeps
  cell text and lets the first label on a cell keep it.
- **tmux swallows kitty graphics**; under `$TMUX` the TUI uses half blocks unless
  `OFFICE_GRAPHICS=kitty`.

## Dev loop

- `mise run office:run` — the TUI over the live server; `mise run office:build` — the executables.
- `mise run office:watch` — the suite on every change; `mise run office:test` once.

## Verify

`mise run office:check` (install, typecheck, tests) — part of `mise run check`. A frame change is
seen, not assumed: run the TUI in a terminal with graphics and look.
