# house — the standalone window over the home and the office

A Godot 4.7 project: two isometric rooms and a panel. The home keeps in sight what the operator's
jots left open, what is coming, and the newest notes; the office shows the crew at their desks and
what waits on the operator. `main.gd` polls, posts and maps the office data, `room.gd` draws a room
from a description (floor, walls, furniture, figures, door), `panel.gd` the lists.

The home is a lived-in room, not a dashboard. `home.gd` owns its state and the order it draws in
(it hands `room.gd` sortable items); `pets.gd` is Nina, Argos and the person (grid walking, perches,
toys, speech lines); `props.gd` is everything the packs do not have, drawn in code (paper, corkboard,
calendar, bubbles, light and weather).

- Notes are slips pinned to the corkboard (four shown, "+N" for the rest); hover or click shows the
  whole note. Open things are stickies on and around the monitor and a stack of paper on the desk
  whose height and small badge follow the count. A reminder's next due time is the wall calendar
  and the caption above the room, in local time.
- Ticking a thing off (after the server says 200) crumples its paper into a ball that arcs into the
  bin; sometimes it misses and Nina chases it in. The last one ticked is a little confetti.
- The room keeps the machine's clock and `weather` from `/api/office` (light, lamp, sky, rain/snow
  in the panes, a sun patch). The plant droops a little as more things are open; no text says so.
- Nina is a black cat with a jewelled collar, Argos a golden dog. Clicking one pets it. Their lines
  are `GET /api/office/pets/:id` for the workspace named "Home", asked at start, once more 45 s later
  if it came back empty, then every 5 min (the server writes a batch when asked, so rarely); lines
  with `{name}` are skipped. With none, or no server, built-in lines in the same voices.

## Law

- **The art is bought and never enters the repo.** It is loaded at runtime from `TLON_ART_DIR`
  (default `~/projects/thatch/packs/x`: the Gridwright interiors, characters and animals packs),
  whose licence forbids redistribution and asks for the "Art by Gridwright" credit the window shows.
  With no art the room is drawn in flat shapes (the pets too) and says so. Whatever the packs lack
  is drawn in code; never add a bought image.
- **It talks to the server only over the operator API**, on `TLON_URL` (default
  `http://127.0.0.1:4040`): the room in view is polled every 5 s — `GET /api/home` or
  `GET /api/office` — and `POST /api/home/:id/done` ticks a thing off. The home also asks
  `/api/office` (weather) and the pets' lines every 5 min. A server that does not answer leaves the
  last data on screen and a quiet line saying so.
- **Rooms.** The window starts in the home, or the office with `--office`. The door in each room, its
  panel button and Tab go between them. A coworker's state is the roster row's `status`
  (`working`, `waiting` on the operator, `idle`, `cold`, `off`; no row is `off`), as `office/kit/crew.ts`
  says it; the crew is `bench`, live seats first. `pause` closes the office.
- **Nothing nags.** No scores, timers, warnings or settings; a pet's bubble fades by itself and stays
  inside the room, never over the panel.

## Dev loop

- `mise run house:run` — over the live server. `mise run house:demo` — on `demo.json` (the home at
  the top level, with `weather`; the office under `office`, shaped like `/api/office`), no server.
  Both take `-- --office`.
- `mise run house:check` — every script loads in headless Godot. Godot is the machine's own, so
  this is not part of `mise run check`.

## Verify

Headless Godot draws nothing. A picture of the real window, with none opened on the desktop:
`gamescope --backend headless -W 1100 -H 700 -- godot --display-driver x11 --path house -- --demo --shot /tmp/house.png`
(`--shot PATH` saves the viewport after 1.5 s and quits; add `--office` for the office). Look at the
picture. The door's click and Tab need a pointer and keys, which that run has not.

User args (after `--`) that fix a state for a picture; `--shot` also freezes the pets' own choices
and seeds their dice (`--seed N` to pick another):

- `--at HH:MM` pretend local time; `--weather clear|partly|cloudy|fog|rain|storm|snow`.
- `--tick-demo` ticks thing 1 off at 0.75 s (a picture at 1.5 s catches the paper in the air);
  `--tick-all` ticks 1, 2, 3 for the confetti; `--bat` makes the paper miss so Nina chases it;
  `--empty` is the demo with nothing open, no notes, nothing coming.
- `--say Nina|Argos` a bubble at 0.3 s; `--nina SPOT[:sleep|sit]`, `--argos SPOT[:...]` start a pet
  at a spot (`pets.gd` `SPOTS`: `sofa`, `desk`, `rug`, `bed`, ...); `--wait SECONDS` when to shoot.
- `--hover X,Y` and `--click X,Y` run the room's own hover and click at a window pixel, so a card, a
  name tag or a pat can be photographed without a pointer.
