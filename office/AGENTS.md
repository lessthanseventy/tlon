# office — the pixel-art room over the server

The office is the server's state as a room: coworkers at desks when they work — and still there,
leaning back with a steaming mug, while their session stays warm (the steam and their screen's
glow fade over the warmth window, from the turn's end as the sim saw it) — in the lounge when
cold, queued at your door when a thread waits on you; the whiteboard holds the worklines, each
marked where it stands (`cardState` in `kit/crew.ts`: ▶ its lead is on it, ⏸ parked and why — the
leaf cap or its lead — ⚑ it needs you; a thread's card names the one key that moves it), the crew
board who is on what; Nina, your cat, keeps you company. TypeScript on bun; one runtime dep, `@xterm/headless` (pure JS, compiled into the binary), for the
terminals the TUI zooms into (`tui/terminal.ts`: tmux control mode on the workspace's tmux, one
linked window at a time, Ctrl-] back to the room).

- `kit/` — what every office surface shares: the snapshot's types (`types.ts`, the shape of
  `Server.Office.status`, served at `GET /api/office`), the data views (`crew.ts`: a workspace's view, the crew, the
  whiteboard's columns), sprites and looks (`sprites.ts`), the colour roles (`palette.ts`), the
  1x canvas and the **frame** a room hands a surface (`canvas.ts`), tlon's own bitmap font in two cuts (`font.ts`), the
  office's life (`sim.ts`: who walks where, Nina's day — a room supplies its geometry as a `Plan`),
  the floor's light as a function of the clock (`daylight.ts`: darkness, lamps lit, `dark`: the pets' bedtime and your pyjamas; lamps register on the `Scene` as they are drawn),
  a pet's temperament (`temperament.ts`: warmth/wits/energy, -2..2, as policy over the sim's chance tables; `pets.ts` resolves `pets.json` — `TLON_PETS`; the cat slot is a cat, rabbit or bird, polled live like `looks.json`, absent means today's room byte for byte),
  what Nina says (`voices.ts`, sweet or sassy by warmth; Argos, the wide room's dog, has his lines in `rooms/wide.ts`),
  drawing people and Nina into a `Scene` (`draw.ts`: what each worker is doing mid-turn, a worker
  making a fuss of a pet), the furniture every room has (`furniture.ts`),
  the home's tiles as pixel art (`homeart.ts`: `TILE_ART`, kind → painter, a missing kind draws plain; `renderHome` the build grid as a Frame, `paintAnnex` the placed tiles as a strip; the snapshot's weather rains and snows on the garden tile),
  the TV's channels (`tv.ts`: the desktop backdrop's ambient shows, retuned for a small screen, and
  an aquarium).
- `rooms/` — rooms built from the kit: `rail.ts`, the desktop's right rail (and the TUI's on a narrow
  terminal); `wide.ts`, the TUI's full-width room (office, floor, meeting room, lounge, a long back
  wall with the whiteboard, notes, calendar, windows on the real weather (`weather` on the
  snapshot), clock, TV), and the pastimes idle coworkers
  move between (`Pastime` in `sim.ts`): a games corner (arcade cabinets, ping-pong), an aquarium,
  the windows, the plants, a chat, the pets, a snack machine, foosball, pool, a reading nook. A home from `home.json` hangs below as an annex (`setHome`; no tiles → the frame is unchanged). A
  thread that ships throws its lead a party; a finished turn high-fives whoever it passes. The
  notes board also carries the crew's chatter (`CorkNote`, from `Server.Office.Corkboard`), kept
  apart from the notes they work from; their suggestions go in the suggestion box beside it, and
  become tickets only when you file them.
  A birthday or anniversary on the calendar feeds (`celebrations` on the snapshot) puts bunting over the
  lounge, a cake on the kitchen counter, and pulls the idle crowd to the cooler and coffee.
- `tui/` — the standalone terminal app (`mise run office:run`), Linux and macOS; `mise run
  office:build` compiles it to one self-contained executable per platform (`office/dist/`).
  `main.ts` is the room, its detail pane's cards (Nina's has her temperament rows, a live preview and `S` to save) and the finder (`/`); `reader.ts` a thread
  full-screen with its composer; `editor.ts` the text editing every input shares; `fuzzy.ts` the
  finder's matcher; `when.ts` reads a schedule's "when" (a cron, or a local time). The arcade's
  cabinets open terminal games (whichever the machine has installed) in the office's own tmux,
  zoomed like a coworker's terminal. It is the
  operator's surface. Its header carries what waits on you (`⚑ N blocking · M to decide`, from
  `GET /api/office/needs`), `i` (or a click on it) opens that queue with each item's own actions, a click on the header's `⚠` warning opens the rack (`H`), and a TUI on an older
  office than main offers `R` to reload itself. Work that lands dark hides behind a server flag,
  read only from the snapshot (`flagOn` in `kit/types.ts`): `B`, build mode, is there only with
  `build_mode` on. A running coworker's card shows their live screen
  (captured, never resized; `c` the conversation, ⏎ step in). Under the room the pane splits: what you clicked on the left, what you can
  do to it on the right — each card's actions (`detail()`) are its keys, its clickable list and
  its docs at once, so they cannot drift apart. A card's rows scroll (`tui/pane.ts`: with the
  selection, or pgup/pgdn and the wheel, `↑/↓ N more` where rows hide); the foot lists the actions
  the column can't show — all of them on a terminal too narrow for it — then the global keys. Popups only where a choice needs a list (the finder).

## Law

- **A room renders to a `Frame`, never to a toolkit.** Art into a 1x RGBA canvas; text, brackets
  and balloons as `Ink` in logical pixels; clicks as `Hit`s. Each surface paints the frame its own
  way (the desktop with Cairo, the TUI as a kitty image or half blocks) and measures its own text
  (`Measure`). A Cairo, Gdk or terminal import under `kit/` or `rooms/` breaks every other surface.
- **Shared means the kit; a room is a surface's own.** Sprites, looks, data views and the frame are
  shared; floorplans, furniture and spots belong to their room, so a bigger room can differ freely.
  Lift room code into the kit when a second room needs it, not before.
- **WCAG 2.2 AA holds for what the TUI shows**, and `test/wcag.test.ts` measures it: every label
  4.5:1 against what is behind it (the painter backs one that would not), text on a type scale
  (`typeFor` in `tui/paint.ts`: small asides, body names and headers, doubled call-outs) that grows
  with the terminal's zoom as far as the room's own scale lets it, no two labels overprinting, no state by colour alone, everything reachable by key.
- **No walk crosses furniture**: a room lists its footprints (`widePlan(w).blocks`) and
  `test/wide.test.ts` walks every route between every spot through them.
- **Every colour is a `ROLE`, read at draw time.** A themed surface hands its roles in with
  `useRoles`; shades between roles come from `tint`, never a literal. The TUI's roles are the
  machine's when it hands them in: `~/.config/tlon/palette.json` (`TLON_PALETTE` to point elsewhere;
  `{ "role": {…} }` or the bare map), re-read within a second of the file — or the link to it — changing,
  so a theme switch follows live. tlon never goes looking for a desktop's theme; the machine links it here.
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
- **The TUI titles its window `tlon office`** (the old title pushed and popped on the terminal's
  stack) so a window manager can match it — glass compositing shows a desktop through the art otherwise.
- **A zoomed terminal resizes only the window it shows** (a throwaway session links just that one
  window); attaching a grouped session would resize every coworker's window to ours.
- **tmux swallows kitty graphics**; under `$TMUX` the TUI uses half blocks unless
  `OFFICE_GRAPHICS=kitty`.

## Dev loop

- `mise run office:run` — the TUI over the live server; `mise run office:build` — the executables.
- `mise run office:watch` — the suite on every change; `mise run office:test` once.
- `mise run office:golden` — re-hash the wide room's golden frames (`test/golden.json`) after a
  change meant to move its pixels. A landing re-hashes them itself after its rebase, so two such
  branches never conflict on the file.

## Verify

`mise run office:check` (install, typecheck, tests) — part of `mise run check`. A frame change is
seen, not assumed: run the TUI in a terminal with graphics and look.
