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

Both reach the **live** server service node (loopback MCP on :4040); the service must be up
(`systemd --user` unit).

- **Door 1 — the MCP tools.** Claude Code's `mcpServers.tlon` entry is `type: http`
  pointing at the channel, with a **`headersHelper`** (`scripts/tlon-cli.sh token`) instead
  of a static bearer. Claude Code runs the helper on every connect and reconnect; it mints a
  **fresh** server token for `(TLON_THREAD, TLON_AUTHOR)` each time, so auth survives a server
  restart and a 401 auto-refreshes. No token is ever written to disk. pi's adapters adapter
  does the same (mints per connect against `/mint`), so both doors are frozen-token-free —
  Claude Code's `headersHelper` and pi's in-adapter mint are the same idea in two shapes.
- **Door 2 — the brief.** [`brief-hook.sh`](brief-hook.sh) is a `SessionStart` hook. Claude
  Code adds its plain stdout to the session context, so on start / resume / clear it renders
  the thread's dossier (the same `Board.in_scope → Brief` as `get_dossier`) and Claude
  re-orients from server. No identity, a down channel, or a missing thread → a silent no-op;
  it never blocks the session.

## The capture reflex (one-ledger Cut 1)

[`capture-hook.sh`](capture-hook.sh) is a `Stop` hook — it runs every turn. It execs
[`cc-capture.ts`](../pi/src/cc-capture.ts) (bun), which reuses pi's `capture.ts` pure core
(delta-slicing, secret redaction, the extraction prompt, tolerant parse) and `mcp.ts`'s
`FunesClient` verbatim — the same reflex pi's `extension.ts` runs on a cadence, adapted to
Claude Code's stateless-per-turn hook model: a per-session watermark is persisted to
`${XDG_STATE_HOME:-~/.local/state}/server-cc-capture/<session_id>` instead of living in a
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

## The heartbeat (server thread #3, 2026-08-27)

[`heartbeat-hook.sh`](heartbeat-hook.sh) is a `PostToolUse` hook — it fires after every tool
call. It execs [`cc-heartbeat.ts`](../pi/src/cc-heartbeat.ts) (bun), which mirrors pi's
`extension.ts` turn_start/turn_end interval: a cadence-gated "here's what's happening" message
posted to the thread during a long single turn, so an agent doesn't go silent (just "thinking")
until Stop. Presence only ever declares twice — thinking at `UserPromptSubmit`, idle at `Stop` —
which reads as frozen on one long turn; the heartbeat is the fix.

Since Claude Code gives each hook fire a fresh process (no long-lived closure to hold an interval
in, unlike pi), the cadence lives in a state file
(`${XDG_STATE_HOME:-~/.local/state}/server-cc-heartbeat/<session_id>`) instead: every `PostToolUse`
call asks "has it been ≥45s since the last post (or since the turn started)?" — `activity.ts`'s
`nextHeartbeatState`/`heartbeatDue` answer that, shared verbatim with pi's side so the two
harnesses' cadence never drifts apart.

The message itself is mechanically derived (which tool, what target — `activityFrom`, no LLM),
then phrased into one personable line by the same out-of-band sidecar completion `capture.ts`
already uses (`phraseHeartbeat`, ollama-cloud flash, no agent turn needed) — a coworker's quick
aside, not a status report. Any hiccup in the sidecar call (unreachable, no key, an empty or
rambling completion) falls back to a plain mechanical line (`fallbackLine`) — unlike the capture
reflex, a heartbeat is never silently dropped, since the message IS the deliverable here.

## Install

Declarative, via home-manager (`flake.nix`), the same merge-not-own pattern as the pi
adapter's `manosWiring`: the `mcpServers.server` entry and the `SessionStart` hook are merged
into `~/.claude` settings idempotently. `home:switch` is the human's.

## Why not a static token / a SessionStart env-mint

A server token is ephemeral (in-memory registry, dies on service restart) and bound to a
`(thread, agent)`. Claude Code expands `${VAR}` in `.mcp.json` only **once at startup** from
the launch environment, and a `SessionStart` hook fires **before** MCP servers connect and
can't set env for them — so neither can carry a refreshing token. `headersHelper` is the only
mechanism that re-mints per connection, which is why the adapter is built on it. (Requires
Claude Code ≥ 2.1.195.)
