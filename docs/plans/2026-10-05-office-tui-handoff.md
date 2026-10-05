# Office TUI — handoff (2026-10-05)

> Done and released as `v0.1.0`; the next round is `2026-10-05-console-retire-and-calendar-handoff.md`.

Where the office work stands after a long session, and what's next. Branch `office-next` in both
tlon and ficciones; nothing pushed (see "Shipping" below).

## Done: tlon's own pixel font

The ask: "Nina + Comic Sans + personality + Atkinson Hyperlegible", pixel-perfect and readable.
`office/kit/font.ts` holds it, hand-drawn as string rows, ASCII 32..126, in two cuts of one design:
`SMALL` 6×9 (capitals 5×7) and `BODY` 7×13 (capitals 5×9, ascenders a row taller). Clipped round
corners, chunky 2×2 punctuation; `I l 1 |`, `0 O o`, `5 S`, `8 B`, `rn m` told apart by shape.

The first try (6×9 at 2×, a terminal-sized 12×18) doubled every label's width and the room could
not hold it; the room now speaks a **type scale** (`typeFor` in `tui/paint.ts`, from each text's size
hint): under 10 → `SMALL` (whiteboard items, crew names, the role on a plate), 10..12 → `BODY` (names,
headers, MEETING, balloons), 13+ → `SMALL` doubled (call-outs: "you - N waiting", the wall clock).
All of it ×`round(cell.h/18)` with the terminal's zoom. The wide room was reshuffled to fit: past
the minimum, width goes mostly to the floor (and the whiteboard over it); wider crew board, exec
desks and seats; **`WIDE_MIN_W` is 540** (narrower terminals get the rail). `wcag.test.ts` now also
fails when two labels overprint.

Text zoom is `min(round(cell.h/18), floor(k/2))`: it follows the terminal's zoom only as far as
the room's scale does, so a zoomed terminal too narrow to scale the room keeps labels apart
(`wcag.test.ts` checks zoomed cells too).

**Parked:** a settings screen for the zoom step (`,` and the "you" card) — not until the room can
hold bigger text than its scale gives it. Letters get iterated with Andrew as they bother him
(renders: `~/.local/state/tlon/tlon-font-*.png`).

## What exists now

- **office/** (tlon) — `kit/` shared by every surface: types, data views (`crew.ts`), sprites,
  palette (+ WCAG `contrast`), canvas/Frame, `sim.ts` (a room's geometry as a `Plan`), `draw.ts`
  (people, Nina, `Scene`), `furniture.ts` (your desk, exec desks, crew board). `rooms/rail.ts` (the
  desktop rail, 144 wide) and `rooms/wide.ts` (the TUI's full-width room; ≥540 logical px; zones
  grow with width; calendar, windows on the real sky, clock, TV, meeting room, kitchen).
  `tui/` — the TUI: picks the wide room at the biggest whole scale ≥2 that fits, else the rail; kitty
  graphics as PNG (ghostty segfaults on `o=z`), half blocks otherwise; talks only to `/api`.
  Tests: `office:check` (19), incl. no-walk-crosses-furniture and WCAG contrast.
- **server/** — `Server.Office` (status, thread_view, aside_spec), `Workspaces.retarget/3`, and the
  whole operator API (`/api/*`, see `Server.MCP.OperatorAPI` moduledoc): every tlon-cli write over
  HTTP. `mise run server:package` → Burrito executables (`burrito_out/tlon_{linux,macos}_{x64,arm64}`)
  with the TUI inside: `tlon` serves, `tlon office` execs the embedded TUI before the VM boots
  (`rel/burrito/plugin.zig`, `Server.Package.Office`). 784 tests green.
- **ficciones** — the desktop rail draws tlon's rail room (kit/rooms linked in; Nix copies them from
  the pinned `tlon` input — `flake:bump` to move it); the shell reads and writes the HTTP API only.
- **GitHub** — `lessthanseventy/tlon`: rebase-only merges, branches deleted on merge; `main`
  protected (PR required, 0 approvals, checks `server` `console` `typescript` `names` strict, linear
  history, no force push/delete, enforced for admins). `.github/workflows/ci.yml` committed, never run.

## Decided, not built

- **The TUI becomes the one surface; the console retires.** `tlon` opens the TUI, `tlon serve` runs
  the server (one file). First slice before retiring the console: threads + full conversation +
  reply, **embedded terminals**, lazygit. Terminals: **tmux control mode** (`tmux -C` streams each
  pane's output, takes keys back — every pane already lives in the server's tmux) + **`@xterm/headless`**
  (pure-JS VT, compiles into the binary everywhere). Not libghostty-vt over FFI (native lib per target).
- **Calendar scheduling**: the wall calendar draws the month; scheduling needs a server model (what
  is scheduled — reminders? coworker runs on a cron?). Ask Andrew.

## Shipping (paused on the TUI work)

README (install, quickstart, `tlon` vs the console, macOS quarantine note), a release workflow (tag
`v*` → `server:package` → GitHub release with the four executables; `server:package` needs a
`mix deps.get` first on a fresh runner), push `office-next`, PR, green CI, rebase-merge, tag
`v0.1.0`. The macOS executables are built but never run on a Mac.

## Session lore that bites

- The Bash tool runs **zsh**: `$var` doesn't word-split (`${=var}`); see the memory note.
- Postgres, the service on :4040, ghostty/hyprctl/grim need the sandbox off.
- Live-checking the TUI: a wrapper script run by `setsid -f ghostty --title=X --gtk-single-instance=false -e script`
  (ghostty re-joins `-e` args), `hyprctl dispatch "hl.dsp.window.close({ window = 'address:…' })"` (the config is Lua: old-style `dispatch` lines fail, quietly when piped away), `grim -g`. `wlrctl` can click.
- Burrito reuses its unpack by version; the `tlon` release version carries the commit.
- `imv` is broken here (EGL assertion); open images in Floorp.
- Parked: ghostty `o=z` crash report (memory note; payload in `~/.local/state/tlon/`).
