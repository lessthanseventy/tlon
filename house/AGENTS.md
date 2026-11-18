# house — the standalone window over the home and the office

A Godot 4.7 project: two isometric rooms and a panel. The home keeps in sight what the operator's
jots left open, what is coming, and the newest notes; the office shows the crew at their desks and
what waits on the operator. `main.gd` polls, posts and maps the office data, `room.gd` draws a room
from a description (floor, walls, furniture, figures, door), `panel.gd` the lists.

## Law

- **The art is bought and never enters the repo.** It is loaded at runtime from `TLON_ART_DIR`
  (default `~/projects/thatch/packs/x`: the Gridwright interiors and characters packs), whose licence
  forbids redistribution and asks for the "Art by Gridwright" credit the window shows. With no art
  the room is drawn in flat shapes and says so.
- **It talks to the server only over the operator API**, on `TLON_URL` (default
  `http://127.0.0.1:4040`): the room in view is polled every 5 s — `GET /api/home` or
  `GET /api/office` — and `POST /api/home/:id/done` ticks a thing off. A server that does not answer
  leaves the last data on screen and a quiet line saying so.
- **Rooms.** The window starts in the home, or the office with `--office`. The door in each room, its
  panel button and Tab go between them. A coworker's state is the roster row's `status`
  (`working`, `waiting` on the operator, `idle`, `cold`, `off`; no row is `off`), as `office/kit/crew.ts`
  says it; the crew is `bench`, live seats first. `pause` closes the office.

## Dev loop

- `mise run house:run` — over the live server. `mise run house:demo` — on `demo.json` (the home at
  the top level, the office under `office`, shaped like `/api/office`), no server. Both take
  `-- --office`.
- `mise run house:check` — every script loads in headless Godot. Godot is the machine's own, so
  this is not part of `mise run check`.

## Verify

Headless Godot draws nothing. A picture of the real window, with none opened on the desktop:
`gamescope --backend headless -W 1100 -H 700 -- godot --display-driver x11 --path house -- --demo --shot /tmp/house.png`
(`--shot PATH` saves the viewport after 1.5 s and quits; add `--office` for the office). Look at the
picture. The door's click and Tab need a pointer and keys, which that run has not.
