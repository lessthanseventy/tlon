# Office TUI — handoff (2026-10-05)

Where the office work stands after a long session, and what's next. Branch `office-next` in both
tlon and ficciones; nothing pushed (see "Shipping" below).

## Next: tlon's own pixel font

**The ask (Andrew):** a custom bitmap font for the office's text — "Nina + Comic Sans + personality +
Atkinson Hyperlegible". Pixel-perfect *and* readable.

**The shape we settled on:**
- A **6×9 cell** — 5×7 capitals, 2 rows of descender, 1 column of spacing — drawn at exactly **2×**,
  so 12×18 screen px: the terminal's own cell height here (ghostty cell 8×18), capitals 14 px. A
  bitmap is only perfect at native × integer; this one is designed for ×2 (×3 on a big zoom).
- **Comic warmth**: rounded corners (one pixel clipped), friendly bouncy shapes.
- **Hyperlegible**: `I l 1 |` and `0 O o` and `5 S`, `8 B`, `rn m` all distinct; open apertures
  (c e a), generous spacing.
- ASCII 32..126 (95 glyphs). Tlon's own — no licence questions (the candidates were MIT/BSD/OFL;
  OFL reserves names on modified versions).

**Where it plugs in:** `office/kit/font.ts` exports `FONT_W`, `FONT_H`, `FONT_ASCENT`, `glyph(ch)`
(rows as bit-numbers, bit `FONT_W-1` the leftmost column). It is currently misc-fixed 6×12 generated
from `/usr/share/fonts/misc/6x12-ISO8859-1.pcf.gz`. Replace it with hand-drawn glyphs — write them as
string rows like the sprites (`"..##.."`), easier to review than hex. `office/tui/paint.ts`:
`textScale(g)` picks the integer scale (now `round(cell.h*0.7/FONT_H)`; for a 9-row font aim at
`round(cell.h/FONT_H)` → 2 here), `inkInto` draws glyphs at `baseline - (FONT_ASCENT - row) * scale`.
`measureFor(g)` gives the room width and `lineHeight`.

**How to judge it:** render the real room — `office/test/wcag.test.ts` shows how to paint a frame
through `inkInto` offline; write a PNG with `office/tui/png.ts` — beside the current 6×12 and
Departure Mono, and iterate on specific letters with Andrew. Keep `wcag.test.ts` green (it measures
every label). Departure Mono, Cozette, Comic Mono, Atkinson Hyperlegible Mono, Spleen and Terminus
are installed (ficciones `825bdb0`) for reference; a comparison of them is at
`~/.local/state/tlon/office-fonts.png`.

**Then:** a settings screen in the TUI (`,` and from the "you" card): the font size step, persisted
in `~/.local/state/tlon/office.json` like `office-workspace` is. (A font *choice* was asked for too —
moot if tlon's font is the one; keep the hook if more fonts come.)

## What exists now

- **office/** (tlon) — `kit/` shared by every surface: types, data views (`crew.ts`), sprites,
  palette (+ WCAG `contrast`), canvas/Frame, `sim.ts` (a room's geometry as a `Plan`), `draw.ts`
  (people, Nina, `Scene`), `furniture.ts` (your desk, exec desks, crew board). `rooms/rail.ts` (the
  desktop rail, 144 wide) and `rooms/wide.ts` (the TUI's full-width room; ≥470 logical px; zones
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
  (ghostty re-joins `-e` args), `hyprctl dispatch focuswindow pid:…`, `grim -g`. `wlrctl` can click.
- Burrito reuses its unpack by version; the `tlon` release version carries the commit.
- `imv` is broken here (EGL assertion); open images in Floorp.
- Parked: ghostty `o=z` crash report (memory note; payload in `~/.local/state/tlon/`).
