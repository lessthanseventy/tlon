# house — the standalone window over the home and the office

A Godot 4.7 project: two isometric rooms and a panel. The home keeps in sight what the operator's
jots left open, what is coming, and the newest notes; the office shows the crew at their desks and
what waits on the operator. `main.gd` polls, posts and maps the office data, `room.gd` draws a room
from a description (floor, walls, furniture, figures, door), `panel.gd` the lists.

The home is a lived-in room, not a dashboard. `home.gd` owns its state and the order it draws in
(it hands `room.gd` sortable items); `pets.gd` is Nina, Argos and the grid they and the person walk
(perches, toys, speech lines); `props.gd` is everything the packs do not have, drawn in code (paper,
corkboard, calendar, phone, notepad, bubbles, light and weather). One file per thing that lives in it:
`person.gd` (the person's activities), `look.gd` (who they are: layered composition, flat fallback,
saved choice), `tv.gd`, `view.gd` (the window's scene), `closet.gd`, `jot.gd`, `menus.gd` (the paper
menu), `focus.gd` (the now card and its timer). `soak.gd` is the scripted check.

- Notes are slips pinned to the corkboard (four shown, "+N" for the rest); hover or click shows the
  whole note. Open things are stickies on and around the monitor and a stack of paper on the desk
  whose height and small badge follow the count. A reminder's next due time is the wall calendar
  and the caption above the room, in local time.
- Ticking a thing off (after the server says 200) crumples its paper into a ball that arcs into the
  bin; sometimes it misses and Nina chases it in. The last one ticked is a little confetti.
- The room keeps the machine's clock and `weather` from `/api/office` (light, lamp, a sun patch).
  The big window over the sofa is the view: sky by local time (dawn, day, golden hour, dusk, night
  with moon and stars), a skyline, hills and a tree, and the weather kinds of `weather.ex` on top
  (sun, drifting clouds, fog, rain with a wet glass, storm flashes, snow that settles on the sill).
  Hover shows the description and `°C (°F)`. Nina sometimes sits on the sill. The plant droops a
  little as more things are open; no text says so.
- **The person** (`person.gd`) walks the pets' grid and picks by state: at the desk in the chair
  (typing) when things are open, on the sofa when clear, watching the TV when something plays, at
  the board or with a coffee now and then (mornings), asleep on the sofa late at night when no
  reminder is open, standing up to stretch when a timer ends, at the desk with a "!" when the phone
  rings. The chair and sofa seat are reached by a short step from a standing cell; pets treat the
  person as air (they never route around or get stuck on him). Click him for a line.
- **The TV** shows what `playerctl` says this machine plays: playing glows with bars, drifting notes
  and an "artist - title" plate; paused is a dim screen; nothing is dark. Click toggles play/pause.
  The person watches, Nina sometimes sits in front.
- **The closet** (wardrobe, or `C`) picks who the person is. With the character-creator pack it
  composes `Layers/<build>/<group>/…png` from `layers.json`'s layer order in GDScript (alpha-stacked,
  scaled nearest) and offers build, skin, hair and colour, beard, top and colour, trousers and
  colour, shoes and colour, hat, extra, the 20 ready-made recipes and a random button; keys up/down,
  left/right, `R`, Enter keeps, Esc leaves. Without the pack: skin, shirt, hat, glasses, scarf drawn
  in code. The choice is saved to `user://house_person.json`.
- **Jotting** (the notepad on the desk, `N`, `/` or Enter): a paper field; Enter sends the text to
  the server (a model reads it, so a pencil scribbles while it waits) and the reply shows as a slip
  for a few seconds. A server that does not answer says "couldn't reach tlon — not kept" and keeps
  the text in the field.
- **Acting on a thing**: click a sticky, a panel row, or a stack (which asks "which one?") for a paper
  menu: Done (the crumple), In an hour, Tomorrow (the paper flies to the wall calendar), Now.
  The panel's tick circle still ticks.
- **The phone** on the desk buzzes with a ring mark while an open reminder has `told_at` (the server
  has nudged it); the window asks for attention once per reminder; click it for that reminder's menu.
- **Now** pins one open thing: large above the monitor and as a card on top of the panel, with a
  timer you start there (click the length for 10 / 25 / 45 min), a progress ring, no sound. Kept in
  `user://house_now.json`; cleared when the thing is done or leaves `open`.
- **Widget** (`--widget`, `W`, `mise run house:widget`): the room alone in a small borderless
  always-on-top window; drag the room to move it, the spot is kept in `user://house_widget.json`.
- Nina is a black cat with a jewelled collar, Argos a golden dog. Clicking one pets it. Their lines
  are `GET /api/office/pets/:id` for the workspace named "Home", asked at start, once more 45 s later
  if it came back empty, then every 5 min (the server writes a batch when asked, so rarely); lines
  with `{name}` are skipped. With none, or no server, built-in lines in the same voices.

## Law

- **The art is bought and never enters the repo.** It is loaded at runtime from `TLON_ART_DIR`
  (default `~/projects/thatch/packs/x`: the Gridwright interiors, characters, animals and
  character-creator packs),
  whose licence forbids redistribution and asks for the "Art by Gridwright" credit the window shows.
  With no art the room is drawn in flat shapes (the pets too) and says so. Whatever the packs lack
  is drawn in code; never add a bought image.
- **It talks to the server only over the operator API**, on `TLON_URL` (default
  `http://127.0.0.1:4040`): the room in view is polled every 5 s — `GET /api/home` (rows carry
  `since` and `told_at`; `done_week` is the count shown quietly in the panel) or `GET /api/office` —
  and posts `POST /api/home/:id/done`, `POST /api/home/:id/later` (`{"until": "hour"|"tomorrow"}`)
  and `POST /api/home` (`{"text"}` → `{"reply"}`, slow: a model reads it). The home also asks
  `/api/office` (weather) and the pets' lines every 5 min. A server that does not answer leaves the
  last data on screen and a quiet line saying so; a post that fails moves nothing.
- **The one local read** besides the server is `playerctl -a metadata` (every 5 s on a background
  thread, never the frame) for the TV, and `playerctl -p NAME play-pause` on a click. No playerctl,
  or nothing playing, is a dark TV. `--demo` never reads it.
- **Rooms.** The window starts in the home, or the office with `--office`. The door in each room, its
  panel button and Tab go between them. A coworker's state is the roster row's `status`
  (`working`, `waiting` on the operator, `idle`, `cold`, `off`; no row is `off`), as `office/kit/crew.ts`
  says it; the crew is `bench`, live seats first. `pause` closes the office.
- **Nothing nags.** No scores, streaks, warnings, sound or settings; the only timer is the one you
  start on a now card. A bubble fades by itself and stays inside the room, never over the panel.

## Dev loop

- `mise run house:run` — over the live server. `mise run house:demo` — on `demo.json` (the home at
  the top level, with `weather`; the office under `office`, shaped like `/api/office`), no server.
  Both take `-- --office`.
- `mise run house:widget` — over the live server as the small always-on-top widget.
- `mise run house:check` — every script loads in headless Godot. Godot is the machine's own, so
  this is not part of `mise run check`.
- `mise run house:soak` — ten simulated hours of the person and the pets on the grid with random
  state changes (nobody on a blocked cell, nobody walking in place, the person always settles), the
  closet's composition over every ready-made recipe, and the POST routes against a local stub; reads
  `playerctl` once. Stdout ends `SOAK OK`.

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
- `--playing "Artist - Title"` / `--paused "..."` a TV state (and no `playerctl`); `--person
  desk|sofa|tv|coffee|sleep|board` the person's activity; `--closet` opens the closet; `--typing
  "text"` opens the jot field (`--sending` shows the scribble); `--reply "text"` the reply slip;
  `--menu ID` the paper menu on thing ID; `--ring ID` rings the phone for thing ID; `--now
  ID[:MINUTES[:DONE_FRACTION]]` pins thing ID with a running timer (nothing saved); `--widget`.
  For `--widget` give gamescope a small size (`-W 400 -H 290`). `TLON_ART_DIR=/none` for no art.
- Not covered by any picture or script: a real pointer (drag, hover feel), the compositor's
  always-on-top and attention request, real `playerctl` toggling.
