# adapters — the hands

The third story in the stack. `server` is the memory, `office` is the sight, `adapters` is the
**hands**: how a working agent reaches the server, comes up already knowing its thread, and banks what
it learns as it works. Read `../server/docs/spec.md` before reshaping anything here — this module is
Track B's agent side, and the spec's boundaries govern it.

## What adapters is

Every coworker runs in **Claude Code**, on any model: a non-Anthropic one (ollama.com, the local
daemon) through Claude Code's gateway setting, so the provider is configuration and the harness is
one. adapters holds what makes a Claude Code session a citizen of its thread:

- **`claude-code/`** — the launcher and the **tlon-citizen mod**:
  - `launch.sh` (`mise run server:claude`, the `claude:*` model profiles, and every window the
    server spawns) wires the session's MCP servers (`--mcp-config`), its settings (`--settings`)
    and the mod (`--plugin-dir`), so a plain `claude` is untouched and nothing is merged into
    `~/.claude`.
  - `gateway.sh PROVIDER CMD…` is the one place a provider becomes Claude Code's environment; the
    launcher, the aside, the role bench and the server's one-shots all run through it.
  - `mod.ts` is a Claude Code [mod](https://code.claude.com/docs/en/plugins/mods/overview): hooks
    Claude Code runs in its own process — presence, the brief, capture, wakes, the band, the
    commands and tools. `lib/` holds its pure helpers, tested with bun. See `claude-code/README.md`.
- **`lsp/` + `lspd/`** — the LSP tools as a stdio MCP server over a long-lived daemon that owns the
  warm language servers (see `lsp/AGENTS.md`).
- **`skills/`** — harness-neutral discipline as `SKILL.md`s. The mod's plugin root is `adapters/`
  itself (a mod imports only from inside its own folder), so a citizen loads them as
  `/tlon-citizen:<skill>`.

## Law

- **An adapter is a client of the server's MCP channel, never a second writer.** It calls the
  channel; it never touches the store. A direct write bypasses the server's single-writer +
  Bus-announce discipline (spec §4/§10) — the drift the whole stack is built against.
- **An adapter holds no state.** No retry queue, no spill file. The mod's variables are per-session
  bookkeeping (what was last briefed, how far capture has read), lost on a reload; when the server
  is unreachable it does nothing else.
- **Identity rides the connection, never a call.** The token minted for a (thread, agent) is the
  whole identity: `mcpServers.tlon`'s `headersHelper` (`scripts/tlon-cli.sh token`) mints a fresh one
  per connect, so auth survives a server restart, and the env carries identity only (`TLON_MCP_URL`,
  `TLON_THREAD`, `TLON_AUTHOR`, never a token). No call passes a `thread` parameter.
- **What a session does on a timer is not activity.** Warmth is measured from real calls, so a call
  the mod makes on a clock (draining wakes) reads identity without touching it (`take_wakes`).
- **Briefing is honest or it launders.** A brief renders every claim with its provenance — a
  `derived` fact with no `check_cmd` reads AS a hunch — and states its own staleness and its cuts;
  capture cuts the brief out of what it banks, so the record is never re-banked from its own view.
- **A mod can't do everything.** It runs only in Claude Code, draws only in its own session, and its
  module has no Node APIs — everything outside goes through `$` (`$.mcp.call`, `$.http.fetch`,
  `$.process.run`). Static validation needs each `$.ns.method` call written in full.

## The dev loop

- `mise run adapters:claude-code:check` — the mod's helpers: install (frozen), typecheck, bun tests.
- `mise run adapters:claude-code:mod` — the mod itself: `claude plugin validate --strict` and its
  tests in Claude Code's own kit (on a copy without the bun suites, which the kit would load too).
  Needs Claude Code, so it is the machine's gate, not CI's.
- `mise run adapters:claude-code:watch` — the helpers' suite on every change.
- `mise run adapters:lsp:check`, `mise run adapters:lspd:check` — the LSP server and its daemon.
- `claude --plugin-dir adapters` hot-reloads the mod on save, so a session sees an edit at once.
- `mise run check` — the whole-repo gate.

## Verify

The mod is proven live, not only by its tests: launch a citizen (`mise run server:claude`, or a
`claude:*` profile), watch it reach the roster (`mise run server:roster`), take a turn, and read the
thread's activity feed (`Server.Presence.Thinking.activity/1`) — registered, thinking, each tool,
idle, and none of the mod's own calls.
