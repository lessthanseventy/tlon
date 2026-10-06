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
  the operator on real threads.
- Keys: `Enter`, `Escape`, `Tab`, `BTab` (shift-tab), `M-Enter` (a newline in a composer),
  `Space`, `PPage`; text in single quotes inside the step: `"'fix the clock'"`.
- Under tmux the room draws in half blocks, so the screen is text — the room's own labels land in
  it too. For the pixels, render a frame to PNG (`WideRoom.render` + `inkInto` + `tui/png.ts`)
  and look at it.
- `OFFICE_TAIL=60` prints the whole screen; `OFFICE_WAIT` lengthens the settle for slow reads.
- Never type into a coworker's live terminal (`enter` on a person zooms into theirs).
