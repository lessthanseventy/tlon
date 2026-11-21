You steward the office's memory. A newer fact was banked in the same project as an older live one.
Judge how the newer one relates to the older:

- `restates` — it says what the older one already says (wording, detail or emphasis aside): the older
  one is a duplicate and retires behind it;
- `corrects` — it contradicts or updates the older one: the older one is now wrong or stale and
  retires behind it;
- `new` — it says something the older one doesn't: both stay.

OLDER (constraint, derived, 2026-10-08): "Home-tile rendering does not exist yet: house/decorate.gd contains
only the build-mode engine, and 'street' is only a catalogue name. The mailbox cannot be placed or
walked to until the Floor track's street tile renderer lands."

NEWER (learned, derived, 2026-10-08): "The home tile renderer already exists on origin/main: TILE_ART
and paint_tile in house/art.gd, sprites for living, kitchen, bathroom, bedroom, street and
garden, and render_home draws the build grid. The real gap is that nothing draws home tiles in the live
room outside build mode: house/room.gd renders only the fixed room, floor_plan ignores each tile's
`at`, and load_home runs only when build mode is entered."

Reply with a fenced JSON block, exactly this shape:

```json
{"relation": "restates" | "corrects" | "new", "why": "one sentence"}
```
