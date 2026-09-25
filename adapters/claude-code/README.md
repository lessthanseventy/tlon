# adapters · claude-code adapter

The hands for **Claude Code** — what makes a `claude` session a server citizen, the peer of
the [pi adapter](../pi). Same **two-doors-one-identity** shape as pi, adapted to Claude
Code's own mechanisms.

## The identity

A session's identity is `(thread, agent="claude-code")`, carried in the environment
(`TLON_THREAD`, `TLON_AUTHOR`) exactly like a pi pane. You get it by launching through
the loop, never by hand:

```
mise run server:claude              # opens a fresh thread, launches claude on it
mise run server:claude -- 42        # JOINS thread 42 (resume a task across a /clear)
```

The launcher `eval`s the export block from `server:spawn` and `exec`s `claude`.

## The two doors

Both doors follow `TLON_MCP_URL` — whichever node spawned the session (the always-up service on
:4040, or a console-launched cockpit brain on :4041) — so a console-launched claude is briefed
from, and posts to, the same `.dev` world.

- **Door 1 — the MCP tools.** Claude Code's `mcpServers.tlon` entry is `type: http`
  pointing at the channel, with a **`headersHelper`** (`scripts/tlon-cli.sh token`) instead
  of a static bearer. Claude Code runs the helper on every connect and reconnect; it mints a
  **fresh** server token for `(TLON_THREAD, TLON_AUTHOR)` each time, so auth survives a server
  restart and a 401 auto-refreshes. No token is ever written to disk. pi's adapters adapter
  does the same (mints per connect against `/mint`), so both doors are frozen-token-free —
  Claude Code's `headersHelper` and pi's in-adapter mint are the same idea in two shapes.
- **Door 2 — the brief.** [`brief-hook.sh`](brief-hook.sh) is a `SessionStart` hook. Claude
  Code adds its plain stdout to the session context, so on start / resume / clear it renders
  the thread's dossier — the `get_dossier` tool itself, called over MCP at `TLON_MCP_URL` by
  `scripts/tlon-cli.sh dossier` (mint → initialize → tools/call, as pi's `mcp.ts` does),
  printed as JSON — and Claude re-orients from server. No identity, a down channel, or a
  missing thread → a silent no-op; it never blocks the session.

## The capture reflex (one-ledger Cut 1)

[`capture-hook.sh`](capture-hook.sh) is a `Stop` hook — it runs every turn. It execs
[`cc-capture.ts`](../pi/src/cc-capture.ts) (bun), which reuses pi's `capture.ts` pure core
(delta-slicing, secret redaction, the extraction prompt, tolerant parse) and `mcp.ts`'s
`TlonClient` verbatim — the same reflex pi's `extension.ts` runs on a cadence, adapted to
Claude Code's stateless-per-turn hook model: a per-session watermark is persisted to
`${XDG_STATE_HOME:-~/.local/state}/tlon-cc-capture/<session_id>` instead of living in a
long-lived closure. Extracted facts are banked `derived`, with `intent`, unbidden. Same
failure discipline as everything else here: no identity, a down channel, a bad completion,
or an unparseable transcript is a silent no-op — a Stop hook must never be why a session
looks broken.

**Cadence floor + tail-loss follow-up.** The Stop hook batches: a delta under `MIN_DELTA_CHARS`
(~2k) accumulates without advancing the watermark rather than paying for a per-turn ollama
call, so nothing is dropped mid-session (the next Stop re-includes it). The one gap is the
*final* sub-floor tail: if a session ends with an un-extracted delta below the floor, it's
never banked. Claude Code exposes a `SessionEnd` hook (fires on session termination) and a
`PreCompact` hook (fires before compaction) — both receive the same `session_id` +
`transcript_path` on stdin as `Stop`, so either could later run `cc-capture.ts` with a
zero-floor "flush" mode to capture that tail. `SessionEnd` is the cleaner fit (it fires after
all turns complete). Deferred — not wired yet; the per-turn Stop reflex covers the common case.

## Install

There is nothing to install: nothing is merged into `~/.claude`. Wiring is **per session** —
[`launch.sh`](launch.sh) (`mise run server:claude`) passes the `mcpServers.tlon` entry via
`--mcp-config` and the hooks via `--settings`, so a plain `claude` stays untouched. Opening a
fresh thread needs a built release (`mise run server:release`): `tlon-cli.sh spawn` goes
through `bin/server rpc`. Once the identity is in the env, `token` (the `headersHelper`) and
`dossier` (the brief hook) work purely over HTTP at `TLON_MCP_URL` — no release needed. The
hook bodies run under `bun` (mise-pinned), which must be on `PATH`.

## Why not a static token / a SessionStart env-mint

A server token is ephemeral (in-memory registry, dies on service restart) and bound to a
`(thread, agent)`. Claude Code expands `${VAR}` in `.mcp.json` only **once at startup** from
the launch environment, and a `SessionStart` hook fires **before** MCP servers connect and
can't set env for them — so neither can carry a refreshing token. `headersHelper` is the only
mechanism that re-mints per connection, which is why the adapter is built on it. (Requires
Claude Code ≥ 2.1.195.)
