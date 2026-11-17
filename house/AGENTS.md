# house — the standalone window over the home

A Godot 4.7 project: an isometric room and a panel that keep in sight what the operator's jots left
open, what is coming, and the newest notes. `main.gd` polls and posts, `room.gd` draws the room,
`panel.gd` the lists.

## Law

- **The art is bought and never enters the repo.** It is loaded at runtime from `TLON_ART_DIR`
  (default `~/projects/thatch/packs/x`: the Gridwright interiors and characters packs), whose licence
  forbids redistribution and asks for the "Art by Gridwright" credit the window shows. With no art
  the room is drawn in flat shapes and says so.
- **It talks to the server only over the operator API**: `GET /api/home` every 5 s and
  `POST /api/home/:id/done`, on `TLON_URL` (default `http://127.0.0.1:4040`). A server that does not
  answer leaves the last things on screen and a quiet line saying so.

## Dev loop

- `mise run house:run` — over the live server. `mise run house:demo` — on `demo.json`, no server.
- `mise run house:check` — every script loads in headless Godot. Godot is the machine's own, so
  this is not part of `mise run check`.

## Verify

Headless Godot draws nothing. A picture of the real window, with none opened on the desktop:
`gamescope --backend headless -W 1100 -H 700 -- godot --display-driver x11 --path house -- --demo --shot /tmp/house.png`
(`--shot PATH` saves the viewport after 1.5 s and quits). Look at the picture.
