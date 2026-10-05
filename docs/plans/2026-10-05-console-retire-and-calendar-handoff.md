# Retire the console, then the calendar — handoff (2026-10-05)

Picks up where `2026-10-05-office-tui-handoff.md` left off. Everything from that session is merged
and released; this is the next round. Start a branch off `main` (protected: PR, four green checks,
rebase-merge).

## Where things stand

- **`v0.1.0` is released** (GitHub release, four Burrito executables; `tlon` serves, `tlon office`
  opens the TUI). The README's quickstart was run as written against a fresh database.
- **The office TUI** (`office/`) has: tlon's own font on a type scale; the machine's live palette
  (`~/.config/tlon/palette.json`); doors in the room — a coworker's monitor / `enter` zooms into
  their live terminal (`tui/terminal.ts`: tmux control mode on a throwaway session linking only that
  window, `@xterm/headless`, Ctrl-] back), `g` lazygit in the thread's worktree (own tmux,
  `-L tlon-office`), the filing cabinet / `f` (done tickets + closed threads); banter
  (`Server.Office.Banter`, weighted kinds of remark on the cheap ollama tier, `TLON_BANTER=1`);
  the lounge TV (the desktop backdrop's shows); Argos the dog; Nina's zoomies; their antics.
- **On the home machine**: `tlon` (ficciones' wrapper) opens the TUI, `tlon console` the console;
  the window titled `tlon office` skips Hyprland glass; ficciones pins tlon at `v0.1.0`.
- **None of the office since the font has had a day of real use** — Andrew is trying it; expect a
  "that's wrong" list (banter cadence/tone, Ctrl-], the pets) to come in alongside this work.

## Next 1: retire the console

`tlon console` (Elixir, `console/`) goes once the office does what Andrew reaches for in it. First
step, before building: **inventory the console's features against the office's** (an Explore agent
over `console/lib` — the cockpit's panes, keys, verbs; then the office's `tui/main.ts` modes) and
show Andrew the gap list. Known gaps already:

- the thread view: ~10 one-line messages in a 14-row pane; needs the full conversation, scrollable,
  wrapped (`Server.Office.thread_view` returns the last 60 — paging means a server read first);
- a real reply composer (today: one input line, `r`);
- hiring/configuring coworkers ("on the desktop for now" in the boss pane);
- whatever else the inventory turns up (triage, health, ledger, the machine terminal, …).

Then: ficciones' wrapper drops `tlon console`, and `console/` + its CI job + its mise tasks go
(check `mise run check:names` and the manual).

## Next 2: calendar scheduling

Andrew's ask: **schedule anything useful** — one agent run, a whole workflow (a workline), a
one-off or cron script — on Oban, shown on the office's wall calendar.

What exists: Oban runs in the service (`TLON_START_OBAN=1`) with a static crontab in
`server/config/config.exs` (e.g. `{"* * * * *", Server.Jobs.Staff}`). OSS Oban has no dynamic cron,
so the likely shape is a `schedule` table (what to run, `cron` or a one-off `at`, enabled, last/next
run, owner) and a per-minute dispatcher job that enqueues what's due — each kind its own worker
(agent run → staff a thread with a prompt; workflow → `Server.Workline.open`; script → run in a
worktree, output recorded). Then operator-API routes, and the TUI: the wall calendar marks days
with something scheduled, the `a` pane lists and edits them. **Read `server/AGENTS.md` and
`server/docs/spec.md` first** — the server has its own law. Open questions to settle with Andrew:
where a script's output goes (a thread? a note?), and whether a scheduled agent run reuses a
standing thread or opens a fresh one each time.

## Lore that bites (all bit this session)

- **The Bash tool is zsh: never put a command in a variable** (`T="tmux -L x"; $T` runs nothing,
  silently under a pipe) — use a function: `t() { tmux -L x "$@"; }`.
- **Run `mise run check` / `server:check` with the sandbox off** from the start (Hex, unix sockets,
  tmux). `$TMPDIR` differs with the sandbox on and off — use explicit paths for logs.
- **Elixir edits go through Menard** (`~/projects/menard/bin/menard edit|write|run …`); Quokka
  reorders `config` calls and can interleave comments — read the result.
- **Driving the TUI**: inside a private tmux in ONE Bash call (the harness reaps tmux servers between
  calls); or ghostty + `hyprctl dispatch "hl.dsp.window.close({ window = 'address:…' })"` (the
  Hyprland config is Lua) + `grim -g`. Never type into a live coworker's pane.
- **The live server**: `mise run server:release && mise run server:restart`; workspace tmux
  (`-L console-workspace-<ws>`) must be started by the service, not the console (a console-started
  one carries `TLON_MCP_URL=…:4041` and the dev db).
- **Releasing**: tag `v*` on `main` → `release.yml`. OTP is pinned exactly (29.0.6) because Burrito
  needs a prebuilt ERTS of the version.
