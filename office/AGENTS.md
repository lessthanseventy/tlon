# office — the pixel-art room over the server

The office is the server's state as a room: coworkers at desks when they work — and still there,
leaning back with a steaming mug, while their session stays warm (the steam and their screen's
glow fade over the warmth window, from the turn's end as the sim saw it) — in the lounge when
cold, queued at your door when a thread waits on you; the whiteboard holds the worklines, each
marked where it stands (`cardState` in `kit/crew.ts`, read from the server's `seat` on each
thread: ▶ its lead is at a desk, ⏸ parked for a seat under the leaf cap, ○ idle — nobody at a desk —
⚑ it needs you; a thread's card names the one key that moves it). DOING is a plain thread someone is
at a desk on; standing duties (`duty`: a schedule's threads, the sheriff's beat) are not work and stay
off the board. The TICKETS column shows one row per epic (`Toy 2/13 → #52 sandbox mode`, from the snapshot's `kind`/`epic_id`/progress), its children hidden until ⏎ opens the epic; a ticket's card names its epic. The crew board says who is on what; Nina, your cat, keeps you company. TypeScript on bun; one runtime dep, `@xterm/headless` (pure JS, compiled into the binary), for the
terminals the TUI zooms into (`tui/terminal.ts`: tmux control mode on the workspace's tmux, one
linked window at a time, Ctrl-] back to the room).

- `kit/` — what every office surface shares: the snapshot's types (`types.ts`, the shape of
  `Server.Office.status`, served at `GET /api/office`), the data views (`crew.ts`: a workspace's view, the crew, the
  whiteboard's columns), sprites and looks (`sprites.ts`), the parts library (`parts.ts`: slots, dials, `rollLook`), the colour roles (`palette.ts`), the
  1x canvas and the **frame** a room hands a surface (`canvas.ts`; its speech balloons are 34×4 with long words hard-broken, placed by `balloon.ts` so none leaves the viewport or overlaps another), tlon's own bitmap font in two cuts (`font.ts`), the
  office's life (`sim.ts`: who walks where, Nina's day — a room supplies its geometry as a `Plan`; a channel down draws the room from the last good snapshot (`Sim.held`: furniture and people stay, the exec desks' plates go blank), dimmed — an outage is never the fire drill; `f` (`play("drill")`) raises a `DRILL`-long one: while `Sim.alarmed`, `closet()` in `rooms/wide.ts` burns, and for the first `PANIC` ticks the crew runs about the room arms up, one scream every few seconds, Nina on the zoomies and Argos with them; then they muster at `plan.muster` with coffee and Argos barks at the smoke),
  the floor's light as a function of the clock (`daylight.ts`: darkness, lamps lit, `dark`: the pets' bedtime and your pyjamas; lamps register on the `Scene` as they are drawn),
  a pet's temperament (`temperament.ts`: warmth/wits/energy, -2..2, as policy over the sim's chance tables; `pets.ts` resolves `pets.json` — `TLON_PETS`; the cat slot is a cat, rabbit or bird, polled live like `looks.json`, absent means today's room byte for byte),
  a coworker's soul (`souls.ts`: `~/.config/tlon/souls/<name>.md` — `TLON_SOULS` — parsed by `## ` headings into `sections`, forgiving; polled live by dir signature like `looks.json`; read-only on the person's card, nothing else consumes it yet, and a soul never decides work),
  what Nina says (`voices.ts`, sweet or sassy by warmth; Argos, the wide room's dog, has his lines in `kit/pets.ts`) — the fallback only: the server's model lines come first (`Sim.hear`, `Server.Office.Pets`), and the pair's exchanges (`duo`) are said turn by turn (`WideRoom.talkOut`),
  a coworker's voice (`seat-voices.ts`: the toy design §2 table — canned banter per seat, the fallback `Sim.onTogether` uses when the server wrote nothing, in `--sandbox` always), and Scharlach the sheriff (`scharlach.ts`: his nameplate, his mug, and a demerit ledger that ticks when a coworker's build goes red — presentation only, on the client, fed by the sheriff's workspace's triage),
  two coworkers the room sees together — at a game, on the couch, at the coffee machine, passing in the hall — are handed to `Sim.onTogether`, and the TUI asks the server what they say (`POST /api/office/talk/:ws`, one model call per conversation, throttled there),
  drawing people and Nina into a `Scene` (`draw.ts`: what each worker is doing mid-turn, a worker
  making a fuss of a pet), the furniture every room has (`furniture.ts`),
  the home's tiles as pixel art (`homeart.ts`: `TILE_ART`, kind → painter, a missing kind draws plain; `renderHome` the build grid as a Frame, `paintAnnex` the placed tiles as a strip; the snapshot's weather rains and snows on the garden tile),
  the TV's channels (`tv.ts`: the desktop backdrop's ambient shows, retuned for a small screen, and
  an aquarium),
  and Uqbar's volume (`uqbar.ts`: sprites, flight, the lounge shelf's extra spine; `viewOf` lifts agent `uqbar` out of the roster into `Agents.uqbar`, so it never gets a desk or a crew row), and its posts as paper aeroplanes (`plane.ts`: pure flight, `freshPosts` off the activity feed, `handoffFrom` off `visits`; `WideRoom.fly` sends one to the thread lead's desk, else its card, and says whether Argos caught it: the TUI earmarks that post and the reader draws 🐾 on its header). The small joys are the room's own, deterministic: a reader settled in the nook for `STRAIGHTEN` ticks stands the knocked spine back up until the next session wakes; Nina swats a book flying low over her (`swatted`), once per pass, and it snaps shut for `FLINCH` ticks.
- `rooms/` — rooms built from the kit: `rail.ts`, the desktop's right rail (and the TUI's on a narrow
  terminal); `wide.ts`, the TUI's full-width room (office, floor, meeting room, lounge, a long back
  wall with the whiteboard, notes, calendar, windows on the real weather (`weather` on the
  snapshot), clock, TV, and — where the wall has room — the poster of the day, `kit/poster.ts`), and the pastimes idle coworkers
  move between (`Pastime` in `sim.ts`): a games corner (arcade cabinets, ping-pong), an aquarium,
  the windows, the plants, a chat, the pets, a snack machine, foosball, pool, a reading nook. The bathroom is a walled room of its own in the bottom-left corner, its door on the hallway (`kit/tiles/bathroom.ts`, geometry and print fade in `kit/bathroom.ts`; the server closet and your office's plant stand just outside it): a tiled floor, a clawfoot tub, a pedestal sink under a mirror and a toilet, each with floor between. Its door stands open while anyone is at it, a coworker
  can idle at its sink, Nina curls up in the dry tub now and then (one of her own places, or `Sim.catDo("tub")`, `u` on her card), and she hops on the tub rim for a drink (`Sim.catDo("drink")`, `b` on her card) — leaving, her wet paws lay `Sim.prints`, which fade with the tick over a minute (longer when she falls in), and Argos follows the trail. A front door stands at the hall's right end (`plan.door`, `kit/door.ts`): the TUI diffs each ok snapshot against the last ok one (`arrivals`) and rings it — a cut (`release.sha` changed) brings pizza, a fuller mailbox the carrier — and now and then a cookie kid or a lost tourist rings on their own; the nearest idle coworker answers, the visitor is sim state (no thread, no ticket). A home from `home.json` hangs below as an annex (`setHome`; no tiles → the frame is unchanged). A
  thread that ships throws its lead a party; a finished turn high-fives whoever it passes. The
  notes board also carries the crew's chatter (`CorkNote`, from `Server.Office.Corkboard`), kept
  apart from the notes they work from; their suggestions go in the suggestion box beside it, and
  become tickets only when you file them. Each is a working coworker's idea (the `suggest` tool),
  not a request, so it never reaches the needs queue (`i`).
  Small talk is said with `Sim.converse`: one balloon per conversation at a time, each up for its
  `readTicks`, in the order written. The TUI keeps the last 50 lines said in its state dir
  (`office-banter`) for the banter log (`/` → "the banter log").
  A birthday or anniversary on the calendar feeds (`celebrations` on the snapshot) puts bunting over the
  lounge, a cake on the kitchen counter, and pulls the idle crowd to the cooler and coffee.
- `tui/` — the standalone terminal app (`mise run office:run`), Linux and macOS; `mise run
  office:build` compiles it to one self-contained executable per platform (`office/dist/`).
  `mise run office:sandbox` (`--sandbox`, or `OFFICE_SANDBOX=1`) runs it on a made-up world, no server: `tui/sandbox.ts` is the
  world and the play-key table, `data.useFake` the one seam in `data.ts`; the play keys (`d e t f n w p c`) shadow the browse keys there only.
  The sandbox keeps its looks, souls and hall in `$TMPDIR/tlon-sandbox/` (the `TLON_*` vars still win), so a pretend hire never reaches the machine's files.
  The hiring hall (`h` from home; `kit/hall.ts` the pure candidate — `roll(seed, locks, taken)` is seeded, no model, no I/O —
  `tui/hall.ts` its card rows): ← pass, ↑ maybe (the pile, `m` browses it), → hire, space locks a row so a pass keeps it. `hall.json`
  (`TLON_HALL`, polled like `looks.json`) holds seed + locks + edits + pile, never the rendered card. → hires in the sandbox only; the
  office's hire call (server `Server.Soul.create`, souls-step-2) is not built yet.
  `main.ts` is the room, its detail pane's cards (Nina's has her temperament rows, a live preview and `S` to save) and the finder (`/`); `talk.ts` what `m` (to a person) and `'` (to the office) post, on the workspace lobby; `reader.ts` a thread
  full-screen with its composer; `editor.ts` the text editing every input shares; `fuzzy.ts` the
  finder's matcher; `order.ts` how list cards sort and group (`s` steps the sort on the crew, a board column and the in-tray; `g` the crew's grouping — the cursor stays on its row); `when.ts` reads a schedule's "when" (a cron, or a local time). `R` on a workline thread reviews its branch: the diff with a line cursor, `⏎`/`a` a note on the line, `A` on the file, `n`/`p` hunks, `N`/`P` files, `s` submits the notes with a verdict (comment, request changes, approve); unsent notes are kept per thread. The crew screen has tabs (`v`): each crew the operator has named, then everyone, the crews not on dimmed; `c` moves the selected coworker to the next crew (or every crew), `n` puts them on a new one by name, and `S` puts the next crew on (also `shifts` in the finder); a click on the header's crew (shown once a workspace has crews) does the same. The finder's `pencils down`, `lights out` (confirmed) and `back to work` are the office's stop controls (`Server.Pause`); while one is on, the header carries its mark (`✎ pencils down` / `◼ lights out`), and a click on it offers back to work. The arcade's
  cabinets open terminal games (whichever the machine has installed) in the office's own tmux,
  zoomed like a coworker's terminal. It is the
  operator's surface. Its header carries what waits on you (`⚑ N blocking · M to decide`, from
  `GET /api/office/needs`), `i` (or a click on it) opens that queue with each item's own actions, a click on the header's `⚠` warning opens the rack (`H`), and a TUI on an older
  office than main offers `R` to reload itself. Work that lands dark hides behind a server flag,
  read only from the snapshot (`flagOn` in `kit/types.ts`): `B`, build mode, is there only with
  `build_mode` on. A running coworker's card shows their activity timeline
  (`timeline.ts`, from the thread view's `activity`, which the harnesses' tool hooks feed: one line per tool call, a glyph and colour per kind, grouped by coworker in their shirt colour, a rule per fresh turn, newest at the bottom, scrolled with the card; `c` the conversation, ⏎ step into their real screen). Under the room the pane splits: what you clicked on the left, what you can
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
- **The TUI talks to the server only over the operator API** (or, in `--sandbox`, to `tui/sandbox.ts`) (`/api/*` on the service's loopback
  port, `TLON_URL` to point elsewhere; `tui/data.ts`). Its read models are `Server.Office`, the same
  function `tlon-cli.sh shell-status` serves the desktop — a new read is a context function and a
  route first, never a query in the client. That is what lets a compiled TUI run with no checkout.
- **A down channel is stale and honest, never empty.** `data.status()` returns the last good snapshot
  marked `ok: false` with `heldAt`; `data.needs()` keeps the last inbox on anything but a 200. Every surface draws
  the held data and the header says its age and `mise run server:restart` (`tui/down.ts`). One refresh
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
