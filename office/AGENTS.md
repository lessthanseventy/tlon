# office — the pixel-art room over the server

The office is the server's state as a room: coworkers at desks when they work — and still there
while their session stays warm, chair turned to the room, leaning back with a steaming mug (the
steam fades over the warmth window, from the turn's end as the sim saw it; their screen is code
mid-turn, a screensaver dot while warm, dark once cold: `screenOf`) — in the lounge when
cold, queued at your door when a thread waits on you; the whiteboard holds the worklines in columns TICKETS · SPEC (intent shares it) · PLAN · BUILD · VERIFY · REVIEW, each
marked where it stands (`cardState` in `kit/crew.ts`, read from the server's `seat` on each
thread: ▶ its lead is at a desk, ⏸ parked for a seat under the leaf cap, ◇ idle — nobody at a desk —
⚑ it needs you, ✓ checking — its full check runs or waits its turn in the machine's queue (`health.checks`; the lines name the workline and come in ticket order; the rack (`H`) lists them with the merge queue and a pending restart as one LANDING & CHECKS list, `kit/rack.ts`: the running landing gate one block — its check folded into its header, then its train's cars, lead first — and each queued landing marked as riding no train or waiting its own turn; status, never a Need), ⤵ landing — in the merge queue, or landed and waiting on GitHub to merge its PR (the
server's `landing` on the thread, kept on REVIEW); a thread's card names the one key that moves it). A plain thread someone is at a desk on
(no workline stage) sits on BUILD, marked doing (a violet tick); standing duties (`duty`: a schedule's threads, the sheriff's beat) are not work and stay
off the board. The TICKETS column is an expandable tree (`Toy 2/13 → #52 sandbox mode`, from the snapshot's `kind`/`epic_id`/progress): ⏎ folds a group's children in place, an in-flight child shows `⚙ on #N` and opens its thread, space opens the group's card; a ticket's card names its epic. The whiteboard's TICKETS sticky is one line per initiative plus "N loose". The crew board says who is on what; Nina, your cat, keeps you company. TypeScript on bun; one runtime dep, `@xterm/headless` (pure JS, compiled into the binary), for the
terminals the TUI zooms into (`tui/terminal.ts`: tmux control mode on the workspace's tmux, one
linked window at a time, ctrl+] to the room).

Each area has its own page under `docs/`; read the one you are changing.

- `kit/` — what every office surface shares: the snapshot's types, the data views (`crew.ts`), the
  whiteboard's items and tips (`board.ts`), sprites, looks and parts, the canvas and frame, the sim
  and everything that lives in it (Nina, Argos, Uqbar, souls, voices, pastimes), the tiles and floor.
  Every roll of chance goes through `rng.ts` (`test/determinism.test.ts` holds it). `docs/kit.md`.
- `rooms/` — `rail.ts`, the desktop's right rail (and the TUI's on a narrow terminal), and `wide.ts`,
  the full-width room with its whiteboard, corkboard, windows, pastimes, parties and small talk.
  `docs/rooms.md`.
- `tui/` — the standalone terminal app (`mise run office:run`, `office:build`, `office:sandbox`):
  cards, the hiring hall, the cast editor, the pet store, the finder, the reader, the keys table, the
  needs inbox, the down-channel handling. `docs/tui.md`.

## Law

- **A room renders to a `Frame`, never to a toolkit.** Art into a 1x RGBA canvas; text, brackets
  and balloons as `Ink` in logical pixels — text is furniture-deep: people and pets are drawn with `Scene.figure`, which marks `Frame.cover`, and a painter leaves a label's pixels under a figure to the art (`over` text, balloons and brackets stay on top); clicks as `Hit`s. Each surface paints the frame its own
  way (the desktop with Cairo, the TUI as a kitty image or half blocks) and measures its own text
  (`Measure`). A Cairo, Gdk or terminal import under `kit/` or `rooms/` breaks every other surface. So does a `node:` import anywhere `rooms/rail.ts` reaches: the desktop bundles that graph under GJS (`test/rail-portable.test.ts`).
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
- **The TUI talks to the server only over the operator API** (or, in `--sandbox`, to `tui/sandbox.ts`) (`/api/*` on the service's loopback
  port, `TLON_URL` to point elsewhere; `tui/data.ts`). Its read models are `Server.Office`, the same
  function `tlon-cli.sh shell-status` serves the desktop — a new read is a context function and a
  route first, never a query in the client. That is what lets a compiled TUI run with no checkout.
- **A down channel is stale and honest, never empty.** `data.status()` returns the last good snapshot
  marked `ok: false` with `heldAt`; `data.needs()` keeps the last inbox on anything but a 200. Every surface draws
  the held data and the header says its age and `mise run server:restart` (`tui/down.ts`). A write while the last status was down is refused up front with that note, never sent to wait out the timeout. One refresh
  runs at a time, with at most one queued behind it (`tui/flight.ts`): a write's follow-up refresh reads what it wrote.
- **Every worn part is data in `kit/parts.ts`** — a new hat is a `PARTS` entry whose test is the data gate, never a branch in `figure()`; `lookOf` must not gain fields (it would restyle everyone).

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
  `OFFICE_GRAPHICS=kitty`. The wide room is kitty-only by default; `OFFICE_WIDE=1` draws it in half
  blocks too (`layoutScreen`), which is how `office:drive` and `release:smoke` reach the door.

## Dev loop

- `mise run office:run` — the TUI over the live server; `mise run office:build` — the executables.
- `mise run office:watch` — the suite on every change; `mise run office:test` once. A test that boots the
  TUI in a tmux pane waits for its first paint with `test/started.ts` (`started`, its own 120 s budget;
  `TUI_TEST` the test's timeout) — never on a step's budget: under the gate a cold `bun tui/main.ts` has
  taken over 25 s to paint. Kill its tmux with `test/kill-server.ts`.
- `office/test/drive/run.sh [walk]` — replays a drive walk (`walk.steps`, `wide.steps`: one `office:drive` step per line) in the sandbox on a throwaway `TMPDIR`; exits 1 on a malformed step or TUI stderr. Re-run it after a UI fix and read the screens; `OFFICE_WIDE=1` / `OFFICE_COLS`/`OFFICE_ROWS` size the window.
- `mise run office:golden` — re-hash the wide room's golden frames (`test/golden.json`) after a
  change meant to move its pixels. A landing re-hashes them itself after its rebase, so two such
  branches never conflict on the file.

## Verify

`mise run office:check` (install, typecheck, tests) — part of `mise run check`. A frame change is
seen, not assumed: run the TUI in a terminal with graphics and look.
