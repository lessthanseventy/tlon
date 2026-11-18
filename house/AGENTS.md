# house — the standalone window over the home and the office

A Godot 4.7 project: two isometric rooms and a panel. The home keeps in sight what the operator's
jots left open, what is coming, and the newest notes; the office shows the crew at their desks and
what waits on the operator. `main.gd` polls, posts and maps the office data, `room.gd` draws a room
from a description (floor, walls, furniture, figures, door), `panel.gd` the lists.

The home is a lived-in room, not a dashboard. `home.gd` owns its state and the order it draws in
(it hands `room.gd` sortable items); `pets.gd` is Nina, Argos and the grid they and the person walk
(perches, toys); `voices.gd` is what they say; `props.gd` is everything the packs do not have, drawn in code (paper,
corkboard, calendar, phone, notepad, bubbles, light and weather). One file per thing that lives in it:
`person.gd` (the person's activities), `look.gd` (who they are: layered composition, flat fallback,
saved choice), `tv.gd` and `hacks.gd` (the TV and its screen hacks), `view.gd` (the window's scene),
`closet.gd`, `jot.gd`, `menus.gd` (the paper menu), `focus.gd` (the now card and its timer), `jar.gd`
(the done jar), `knock.gd` (Nina's one nag), `door.gd` (what comes through the office door),
`rhythm.gd` (the day's two beats and their slips), `layout.gd` (the furniture and the rules of placing it),
`decorate.gd` (the catalogue and the pointer work of decorating). `soak.gd` is the scripted check.

- Notes are slips pinned to the corkboard (four shown, "+N" for the rest); hover shows the
  whole note, a click opens the board card. Open things are stickies on and around the monitor and a stack of paper on the desk
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
  (typing) when things are open, on the sofa when clear, watching the TV now and then when nothing
  is open (10:00-23:00), at the board or with a coffee now and then (mornings), asleep on the sofa
  late at night when no reminder is open, standing up to stretch when a timer ends, at the desk with
  a "!" when the phone rings. The chair and sofa seat are reached by a short step from a standing
  cell; pets treat the person as air (they never route around or get stuck on him). Click him for a
  line. Seated on the sofa he sorts after the window, so head and shoulders show over the back.
- **The TV** (`tv.gd`, `hacks.gd`) is just a TV: it knows nothing of the computer. It is on while
  the person watches and off otherwise and in the deep night; its card's button turns it on for 90 s
  or changes the channel. On, it runs one of the code-drawn screen hacks (`spectrum stars plasma logo
  rain life pipes moire scope sunset fireworks toasters note`), a new one every 2-4 minutes through
  a short static flicker, never the same twice in a row. Hover shows the same hack large, no text.
  Add a hack: a `_name(c, q, t)` drawer in `hacks.gd` and its name in `NAMES`. Nina sometimes sits
  in front of it when it is on.
- **The done jar** (`jar.gd`) is a glass jar on a shelf over the bin: one marble per thing done this
  week (`done_week`, drawn up to 27, colours stable per week). A thing done drops a marble with a
  bounce and a clink mark; a new week (Monday) starts it empty, quietly. Hover: "N done this week".
  The count is `done_week`; names come only from a `done` list in the status.
- **Cards** (`card.gd`; blocks built in `home.gd` `card_blocks`): a click on the calendar, jar, window,
  clock, board (cork, a note or the "+N" tag), large plant or TV opens one paper popup near it, at
  readable size; hover keeps the small tooltip and the pointing hand. One at a time: Esc, a click
  outside, or a click on another thing closes it (the same thing again too); none opens while a menu,
  the notepad, the closet, decorate mode or the day's slip is up, and one open closes when they do.
  Calendar: the month grid with a dot on each day a reminder falls (a repeating one on each of its days)
  and the next five coming up (day, time, text, "every week"). Jar: the count, and the names newest
  first when the status has `done` (`[{text, done_at}]`; ten shown). Window: the weather in words
  and `°C (°F)`. Clock (a `clock` piece on a wall): the time and date, the next reminder and how long
  ("in 2 h 10 min"). Board: every note, five a page with `<` `>`. Plant: when a repeating reminder
  that mentions water or the plant is next due, else a plain line. TV: the screen hack playing and a
  Next (or Turn on) button; no play state, no media titles. The pets' bowls and bed have none.
- **Argos celebrates** every done thing: runs to the desk and hops, with a line. He greets the person
  at the door when he comes in. **Nina's one nag**: when the oldest open thing without a future
  `due_at` has sat over 3 days (`since`), she now and then (checks every 3-10 min, 4 h apart at
  most, 08:00-21:00, never at night) walks to the desk and knocks that sticky onto the floor
  (`knock.gd`); one at a time; it lies there until clicked, which gives its paper menu and puts it
  back on the desk. It is not kept across restarts, only the time of the last knock. She also sits on
  the notepad now and then while the jot field is closed.
- **The door**: while the home is in view `/api/office` is read every 60 s. When something waits on
  the operator (a roster row `waiting`, a thread with `awaiting` or `prompt`, or `awaiting` > 0) a
  coworker leans in at the door, waves with a "!" and a one-line caption (the prompt summary or the
  thread title); click goes to the office; they leave when nothing waits. A paused office (`pause`)
  sends nobody. Each new entry in `landings` (`[{ref, subject, landed_at}]`, newest first; the first
  read only records what is there) sends a paper plane through the door to the desk, with the subject
  on a tag; click puts it away, it also goes by itself after 5 min.
- **The day's rhythm** (`rhythm.gd`), each beat once a day, remembered in `user://house_rhythm.json`:
  at the server's `home_list_at` (`GET /api/settings`, `knobs[].key`; empty never; 17:30 until
  read) he comes home through the door with a bag, Argos greets him, and a slip of what is still open
  unrolls for 14 s (click an item for its menu, click the slip or Esc puts it away); for 3 h after
  that time at most. In the morning (first run after 05:30, or the clock passing 08:00, before noon)
  he stretches and a slip shows what is coming today. Late at night with nothing due the lights dim
  further, he sleeps, the TV is off, Nina sleeps on the sofa and Argos on the rug beside it. Coming
  back to the home from the office after 20 s also brings him in through the door.
- Small things: a "water the plant" thing done perks the plant up for 10 min with a can and drops;
  a note, open thing or reminder due today that says birthday or anniversary hangs bunting; the
  window gets lights in December, a pumpkin from 25 Oct, hearts 10-14 Feb.
- **The room** is 10x10 cells and, in the 1100x700 window beside the panel, drawn at scale 2 (scale 3
  needs 976 px). `layout.gd` holds what stands in it: the fixed pieces the behaviour is tied to
  (desk, office chair, TV stand, sofa, wardrobe, bin, large plant, floor lamp; also the door, window,
  board, calendar, jar and the pets' corner, none of them movable) and the plain ones (the rest of
  the default room: armchair, plants, paintings, clock, rugs, fireplace with its fire, bookshelf,
  piano, dining set, mirror...), plus the wall and floor style. `room.gd` draws what it hands over.
- **Decorate** (`D`, or `--decorate`; the home only, not the widget): the side panel becomes the
  catalogue (`decorate.gd`): wall and floor styles, `reset`, and every placeable piece of the pack's
  index grouped and scrolled, a piece's four sides (or a rug's two, a wall piece's two) one entry. Click a piece, a ghost follows the pointer
  snapped to the cell (red where it cannot go), click places it and keeps it chosen, `R` turns it
  (right click with nothing under the pointer lets go). Click a placed piece to pick it up and
  click to put it down; `X`, Delete or right click on a placed piece removes it; `Esc` or `D`
  leaves. A fixed piece says "that one stays". Furniture on the floor blocks its cells for Nina,
  Argos and the person (`pets.blocked_cells`, from `layout.blocked`; they route around it, rugs
  and wall pieces block nothing); a placement is refused on a cell someone stands on, on any pet or
  person spot, on a fixed piece, and when it would cut a spot (or someone) off from the door
  (flood fill). A fireplace and wall pieces go on the wall their side names (ne: top row, nw: left
  column), not on the segments the board, window, calendar, jar and door use.
  The layout is saved on every change to `user://house_layout.json`
  (`{"v": 1, "wall": "brick", "floor": "oak", "pieces": [{"p": "bookshelf", "f": "se", "c": 9, "r": 0}]}`:
  `p` the catalogue name, `f` the side or `""`, `c`/`r` the back cell; the fixed pieces are not
  saved) and read at start; a missing or unparsable file, an unknown name or side, or a piece that can no longer
  stand is skipped and the rest kept. `--demo` and `--shot` neither read nor write it unless
  `--layout PATH` names a file (read and written). With no art there is no decorating (one line
  says so) and the default room is boxes.
- **The closet** (wardrobe, or `C`) picks who the person is. With the character-creator pack it
  composes `Layers/<build>/<group>/…png` from `layers.json`'s layer order in GDScript (alpha-stacked,
  scaled nearest) and offers build, skin, hair and colour, beard, top and colour, trousers and
  colour, shoes and colour, hat, eyewear, scarf, backpack and apron (worn together, each with none), the 20 ready-made recipes and a random button; keys up/down,
  left/right, `R`, Enter keeps, Esc leaves. Without the pack: skin, shirt, hat, glasses, scarf drawn
  in code. The choice is saved to `user://house_person.json` (an old `extra` loads into its slot).
  With the hero-creator pack there is a second tab, "hero" (Tab or a click switches; absent without the
  pack): its ready-mades, build, skin and every group of `layers.json` (cape, chest, gloves, beard, hair,
  helmet, legs, shoes, shoulders, weapon) as a style row and a colour row (the colours are the ones that
  style comes in; "none" where a piece is optional), and random. Keep wears the tab it was kept on: the
  file holds the everyday look at the top level, `"wear": "everyday"|"hero"` and `"hero": {...}` (a hero
  look with the pack gone falls back to the everyday one). Animations, columns, fps and layer order are
  read from the pack's `layers.json`. A hero has no sit, type, eat, wave, cheer, pickup or talk: he
  stands on the floor cell he would walk to (no seat offset) and the action maps to `HERO_ACT` in
  `look.gd` (desk typing: `ready`; sofa, TV, coffee, sleep, talk: `idle`; wave: `block`; cheer: `cast`;
  pickup: `thrust`; walk: `walk`). Changing between the two re-places the person.
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
- **Widget** (`--widget`, `W`, `mise run house:widget`): the room alone in a borderless always-on-top
  window of 656x432, exactly the room at scale 2 so it stays crisp; drag the room to move it, the
  spot is kept in `user://house_widget.json`.
- Nina is a black cat with a jewelled collar (smart, sassy, wins every argument), Argos a golden dog
  (sweet, not bright). Clicking one pets it. Their lines are `voices.gd`: `GET /api/home/pets`, a batch a
  model wrote for the home as it is now, `{Nina: {occasion: [lines]}, Argos: {...}, duo: [[
  "Nina: ...", "Argos: ..."]]}` (`{}` until the first exists). Asked at start, every 20 s while empty
  (3 min, then every 5 min), else every 5 min, and once 60 s after the open list changes; a failure or
  `{}` keeps what is held. Occasions: `pet` (click), `wake` (clicked or woken), `muse` (unprompted),
  `done` (Argos names the thing; `all_done` for the last), `old` (Nina as she knocks), `jot` (note sent),
  `ring`, `home` (Argos at the door), `morning`, `tv`, `night`; the pet nearest and awake speaks, never
  two at once. `{thing}` is the thing's text, trimmed; a line with it and no thing is skipped. A line
  never repeats until the pet's others for that occasion have been used (reset on a new batch), nor
  twice in a row; a bubble wraps and stays 3.5-9 s by length. Now and then both awake and idle play a
  `duo`, alternating bubbles. Built-in lines (one or two) are only for a pet and occasion the server gave
  nothing for; none and no line means no bubble. `--demo` serves `pets` from `demo.json`.

## Law

- **The art is bought and never enters the repo.** It is loaded at runtime from `TLON_ART_DIR`
  (default `~/projects/thatch/packs/x`: the Gridwright interiors, characters, animals and
  character-creator packs),
  whose licence forbids redistribution and asks for the "Art by Gridwright" credit the window shows.
  With no art the room is drawn in flat shapes (the pets too) and says so. Whatever the packs lack
  is drawn in code; never add a bought image.
- **It talks to the server only over the operator API**, on `TLON_URL` (default
  `http://127.0.0.1:4040`): the room in view is polled every 5 s — `GET /api/home` (rows carry
  `since` and `told_at`; `done_week` fills the jar, an optional `done` list names what was done) or `GET /api/office` —
  and posts `POST /api/home/:id/done`, `POST /api/home/:id/later` (`{"until": "hour"|"tomorrow"}`)
  and `POST /api/home` (`{"text"}` → `{"reply"}`, slow: a model reads it). The home also asks
  `/api/settings` and `/api/office` (weather, the door) every 60 s and `/api/home/pets` on its own schedule (above). The house has no local reads: it talks only to the server. A server that does not answer leaves the
  last data on screen and a quiet line saying so; a post that fails moves nothing.
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
  closet's composition over every ready-made recipe, decorating (placement rules, reachability from the door, random layouts walked on, saving and loading, the pointer work), the jar, the cards (each opens from its hit area, one at a time, none over a menu), the hero look, every layer file reachable from the closet, the knock rules, the day's rhythm, the door and the TV hacks, and the POST and GET routes against a local stub. Stdout ends `SOAK OK`.

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
- `--say Nina|Argos` a bubble at 0.3 s (`--occasion NAME` for its line; `--duo` plays an exchange; `--no-voices` drops the demo batch to show the built-ins); `--nina SPOT[:sleep|sit]`, `--argos SPOT[:...]` start a pet
  at a spot (`pets.gd` `SPOTS`: `sofa`, `desk`, `rug`, `bed`, ...); `--wait SECONDS` when to shoot.
- `--hover X,Y` and `--click X,Y` run the room's own hover and click at a window pixel, so a card, a
  name tag or a pat can be photographed without a pointer.
- `--tv on|off`, `--hack NAME` a TV state and screen hack (`spectrum stars plasma logo rain life pipes moire scope sunset fireworks toasters note`); `--jar N` the jar's marbles, `--jar-drop` one more at 0.7 s; `--knocked ID` that sticky on the floor with Nina; `--wave "text"` a coworker at the door; `--plane "title"` a landed plane; `--homecoming` / `--morning` the day beats; `--date MM-DD` the season; `--visitor` feed the demo office to the door; `--person
  desk|sofa|tv|coffee|sleep|board` the person's activity; `--closet` opens the closet (`--tab hero` on its hero tab); `--look k=v,...` sets look keys for the picture (not kept; `wear=hero,recipe=mage` then group keys such as `weapon=staff,weapon_c=royal` for a hero); `--card calendar|jar|weather|clock|board|plant|tv` opens that card at 0.45 s; `--then ACT` switches `--person` to ACT at 0.3 s so he is caught walking; `--typing
  "text"` opens the jot field (`--sending` shows the scribble); `--reply "text"` the reply slip;
  `--menu ID` the paper menu on thing ID; `--ring ID` rings the phone for thing ID; `--now
  ID[:MINUTES[:DONE_FRACTION]]` pins thing ID with a running timer (nothing saved); `--widget`;
  `--layout PATH` a layout file; `--decorate` opens decorate mode, `--pick NAME[:SIDE]` chooses a piece
  and `--cell COL,ROW` puts the ghost there.
  For `--widget` give gamescope `-W 656 -H 432`. `TLON_ART_DIR=/none` for no art.
- Not covered by any picture or script: a real pointer (drag, hover feel), the compositor's
  always-on-top and attention request, the real hour of the beats.
