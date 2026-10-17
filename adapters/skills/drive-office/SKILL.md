---
name: drive-office
description: Drive the office TUI (the operator's surface) headlessly from a session — send keys, read the screen back as text — to verify a change end to end, not just by its tests. Runs in a private tmux server of its own, never in the operator's terminal.
---

# Driving the office

`mise run office:drive -- STEP...` (`scripts/office-drive.sh`) starts the office in a private tmux
server, sends each step's keys (tmux `send-keys` syntax), prints the bottom of the screen after
each, and tears everything down — all in one call:

```bash
TLON_URL=http://127.0.0.1:4041 mise run office:drive -- "/" "'108'" "Enter" "r" "'looks right'" "Enter"
```

- **Point it at a scratch server**, not the service, for anything that writes: `mise run
  server:dev` serves the dev db on :4041. Against the service (the default URL) you are acting as
  the operator on real threads. The TUI's own files are safe either way: the drive runs on a
  throwaway copy of `~/.config/tlon`, so pets, the store, the hall and souls it writes go to the copy,
  and on a tmux of its own (`TLON_OFFICE_TMUX`), so the docs, games and dump it opens never land in the
  operator's office. The dump's editor is `$VISUAL`/`$EDITOR`: set it to a script to drive one.
  To read back what a drive saved (home.json, looks.json), `OFFICE_KEEP=1` keeps the copy and
  prints `kept: DIR`; the files are under `DIR/config/tlon/`.
- Keys: `Enter`, `Escape`, `Tab`, `BTab` (shift-tab), `M-Enter` (a newline in a composer),
  `Space`, `PPage`; text in single quotes inside the step: `"'fix the clock'"`.
- Under tmux the room draws in half blocks, so the screen is text — the room's own labels land in
  it too. For the pixels, render a frame to PNG (`WideRoom.render` + `inkInto` + `tui/png.ts`)
  and look at it.
- The rail room is what tmux gets. The wide room — the front door and its visitors, the bathroom,
  Argos — draws only under kitty graphics, so for anything there set `OFFICE_WIDE=1` (a 280x75
  window, the wide room in half blocks) and `OFFICE_TEXT=1` (every row, pixels dropped: "Ding
  dong!", "Pizza! …", the wall's `NOTES n` read as lines). Doors, bubbles and who stands where
  come out as balloon text and labels; a shape is not text, so to see one render a frame.
- `OFFICE_TAIL=60` prints the whole screen; `OFFICE_WAIT` lengthens the settle for slow reads.
- `"wait:TEXT"` sends no keys: it waits (30 s at most) until the screen shows TEXT. Open the finder
  only after `"wait:‹ Machine ›"`: until the TUI's first snapshot lands it lists nothing.
- Never type into a coworker's live terminal (`enter` on a person zooms into theirs).
