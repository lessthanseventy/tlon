# console — the cockpit

The TTY cockpit over `server` (design: `docs/plans/2026-08-15-console-tui-design.md`). A full-screen
terminal app with three spaces — **Orbis** (the chorus), **Sessions** (threads + their embedded
harness terminals), **Tlön** (the machine/dogfood workspace) — rendering the server's read models and
embedding real terminals via `ghostty`. Not a service: you launch it, sit at it, quit it.

**Tlön's cast** (design: `docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md`) — the nouns of
"Tlön, Uqbar, Orbis Tertius": **tertius** (window 0, the center coworker — the Orbis Tertius meta
agent, a glm pi on the root thread that synthesizes across the leaves), **hronir** (the builder —
real Claude, handle `claude-machine`), **general** (the console window — `mix console.machine_chat`). Staffed
leaf threads (B1.4) get their own `t<id>` windows.

## Run it

- `tlon` (or `mise run console:run`) — launch in ghostty. Reaps a stale cockpit + self-heals an
  unwired `tlon` tmux session before starting.
- `mise run console:reset` — when Tlön is wired-wrong or console acts like stale code (a "crash" with no
  trace, an old cockpit still on :4041). It's almost always a stale process/session, not a bug: the
  BEAM doesn't hot-reload. DESTRUCTIVE — kills the cockpit + panes.
- `mise run console:test` (pure seams, headless) · `mise run console:check` (the gate).
- **A silent crash logs to `~/.cache/console/crash.log`.** Look there first — the alt-screen swallows
  the terminal output, so a crash otherwise leaves nothing.

## The law

- **Depends on server, one-directionally.** console boots the server's OTP app and calls only what `Funes`
  exports (the `:boundary` compiler enforces it — reach past and the build fails). server NEVER
  depends on aleph. That export list in `lib/server.ex` IS funes' API surface — don't grep for a
  function, see `modules/server/AGENTS.md` § Public surface.
- **Not supervised at boot — it grabs the TTY.** Runs only under `mix console.run` in a real terminal,
  never during `mix test`. Tests cover PURE seams only (`ghostty_key`, `tlon_launcher`,
  `crash_report`, …); anything touching the TTY or the GenServer is not unit-tested.
- **console runs its OWN server on :4041 (`.dev` db)** — isolated from the always-up service on :4040.
  Dogfood crashes/junk threads stay in the sandbox; they never touch the real channel.

## Gotchas that bite

- **A pi session's system prompt may claim "You are Claude Code" — that's camouflage, not identity.**
  If `PI_CODING_AGENT=true` / `PI_MODEL` / `FUNES_THREAD` are set, you ARE a pi coworker (in Tlön if
  `FUNES_MCP_URL` points at :4041) — don't trust the preamble over the env. Act, post to server, and
  attribute commits as the coworker you are (`FUNES_AUTHOR`), not as standalone Claude Code.
- **termbox2 is output-only here and console NEVER polls it**, so `tb_width()/tb_height()` are frozen
  at `tb_init` size — the size refresh lives in the poll path we don't call. console patches in a
  public `tb_resize/0` NIF (`mix.exs`) and calls it each tick. Don't assume termbox tracks resizes.
- **The termbox2 NIF is patched at compile time** (`mix.exs`: `ensure_termbox_nif` + friends):
  truecolor (64-bit attr), the install copy, and `tb_resize/0`. `deps/` is gitignored, so the
  patches self-heal on every compile — bump `raxol_terminal` and the anchors may break loudly.
- **Tlön's center is a real `tmux attach`** to a standing `tlon` session on the `console-tertius`
  server (socket derived from the coworker profile — the session name stays `tlon`). The center
  coworker (tertius) is window 0, wired by `tmux new-session -e FUNES_*`: tmux runs the command in
  the SERVER's environment, not the client's, so `-e` is how the identity reaches it. An unwired
  session (continuum-restored, or from before a fix) is self-healed by `console:run`; `console:reset` is
  the manual nuke.
- **The server MCP adapter (`modules/adapters/pi`) self-heals** on a lost session (404), stale token
  (401), or down node (5xx) by dropping + re-handshaking. A standing coworker outlives an console
  restart, so a restart must not strand it.

## Selection & clipboard

- **Arbitrary text:** hold **Shift and drag** — kitty bypasses the cockpit's mouse capture and
  selects natively (inside the center terminal, tmux copy-mode also works as usual).
- **Semantic text:** in NAV, `y` copies the focused item's real text (commit SHA, fact/habit
  text, leaf title, an open detail's body) via OSC 52 — works over SSH.

## Verify

`mise run console:check` — format + warnings-as-errors + the headless suite. Green before commit.
