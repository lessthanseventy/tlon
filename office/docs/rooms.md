# office/rooms/ — the rail and the wide room

`rooms/` — rooms built from the kit: `rail.ts`, the desktop's right rail (and the TUI's on a narrow
terminal); `wide.ts`, the TUI's full-width room (office, floor, meeting room, lounge, a long back
wall with the whiteboard, notes, calendar, windows on the real weather (`weather` on the
snapshot), clock, TV, and — where the wall has room — the poster of the day, `kit/poster.ts`), and the pastimes idle coworkers
move between (`Pastime` in `sim.ts`): a games corner (arcade cabinets, ping-pong), an aquarium,
the windows, the plants, a chat, the pets, a snack machine, foosball, pool, a reading nook. The bathroom is a walled room of its own in the bottom-left corner, its door on the hallway (`kit/tiles/bathroom.ts`, geometry and print fade in `kit/bathroom.ts`; the server closet and your office's plant stand just outside it): a tiled floor, a clawfoot tub, a pedestal sink under a mirror and a toilet, each with floor between. Its door stands open while anyone is at it, a coworker
can idle at its sink, Nina curls up in the dry tub now and then (one of her own places, or `Sim.catDo("tub")`, `6` on her card), and she hops on the tub rim for a drink (`Sim.catDo("drink")`, `5` on her card) — leaving, her wet paws lay `Sim.prints`, which fade with the tick over a minute (longer when she falls in), and Argos follows the trail. A front door stands at the hall's right end (`plan.door`, `kit/door.ts`): the TUI diffs each ok snapshot against the last ok one (`arrivals`) and rings it — a cut (`release.sha` changed) brings pizza, a fuller mailbox the carrier — and now and then a cookie kid or a lost tourist rings on their own; the nearest idle coworker answers, the visitor is sim state (no thread, no ticket). A home from `home.json` is drawn on the floor below the office at its absolute cells (`setHome` re-plans the sim: `floorPlan`'s third param adds each tile's `HOME_BLOCKS` at its cell and, with a street under the front door and a living tile, `doors`/`walk` between them; `paintFloor`, `kit/home.ts` `cellPx`/`OFFICE_ROWS`; `loadFloor` shifts a pre-floor `home.json` below the office in memory; build mode starts at `OFFICE_ROWS` and refuses rows above it; no tiles → the frame is unchanged). A
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
