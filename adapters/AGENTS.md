# adapters — the hands

The third story in the stack. `funes` is the memory, `aleph` is the sight, `adapters` is the
**hands**: how a working agent reaches funes, comes up already knowing its thread, and banks what it
learns as it works. Read `../funes/docs/spec.md` and
`../../docs/plans/2026-08-15-pi-integration-and-funes-mcp-design.md` before reshaping anything here —
this module is Track B's agent side, and the spec's boundaries govern it.

## What adapters is, and is not

**adapters is vendor-agnostic by identity.** funes' channel is MCP — an agent-agnostic protocol, not a
pi API — so *any* harness can be a citizen of a thread. adapters holds **one adapter per harness**, each
a thin bridge from that harness's lifecycle to funes' one sovereign channel:

- **`pi/`** — the pi adapter (built). A TypeScript extension for `pi`
  (`github.com/earendil-works/pi`): `extension.ts` registers at session start, briefs before the
  agent runs, and shows funes state in the widget. pi is the harness for codex / glm / kimi / any
  model that speaks it.
- **`footer/`** — a dense 2-line pi statusline (full model name, context bar, I/O, branch,
  statuses). NOT a funes adapter — a generic footer, kept in its own package so a self-contained
  coworker (the Tlön profile drops `adapters/pi` to sever funes) still gets it. It reads pi's own
  model/context/session surface, not funes.
- **`claude-code/`** — the Claude Code adapter (built). Same two doors, adapted to Claude Code's own
  mechanisms: the MCP tools via `mcpServers.funes` `type:http` with a **`headersHelper`**
  (`scripts/tlon-cli.sh token`) that mints a FRESH token per connect — so unlike pi's static bearer,
  auth survives a funes restart — and the brief via a `SessionStart` hook (`brief-hook.sh`). Both are
  scoped to the session by `funes:claude`'s `--mcp-config`/`--settings` launch flags, so a plain
  `claude` is untouched and nothing is merged into `~/.claude`. See `claude-code/README.md`.

**The rules that hold across every adapter — break one and adapters stops being the hands:**

- **An adapter is a client of funes' MCP channel, never a second writer.** It calls the channel; it
  never touches the shared SQLite. A direct write bypasses funes' single-writer + Bus-announce
  discipline (spec §4/§10) — the drift the whole stack is built against.
- **An adapter holds no state.** No retry queue, no spill file. When funes is unreachable it surfaces
  the failure and does nothing else — a client-side buffer is the second log this design removes
  (pi doc §2a).
- **No harness's specifics leak into another's.** A model, a provider, a harness are configuration
  (spec §8). The shared discipline lives in the skills (harness-neutral prose); only the lifecycle
  glue is per-adapter.
- **Identity rides the connection, never a call.** The token minted for a (thread, agent) is the whole
  identity. No adapter ever passes a `thread` parameter; misdirection is unrepresentable (pi doc §2a).
- **Briefing is honest or it launders.** A brief renders every claim with its provenance — a `derived`
  fact with no `check_cmd` reads AS a hunch, never as flat truth — and states its own staleness and
  its cuts, or generation N's guess becomes generation N+1's ground truth (pi doc §2b).

## The two doors, one token

An adapter reaches funes through **two MCP connections that share one bearer token**, and the token —
not the transport — is the identity:

1. **The extension's own client** calls `register` (once, at session start) and `get_dossier` (to
   brief), deterministically, before the model runs. There is no pi API to invoke a tool from a hook,
   so the extension is itself a small MCP client (`pi/src/mcp.ts`).
2. **`pi-mcp-adapter`** exposes funes' write verbs (`post_message`, `bank_fact`, `raise_issue`,
   `record_done`) to the *model* as first-class tools.

Because funes binds a session to the **token** (`Funes.MCP.Tokens.bind_session/2`), not to a transport
connection, `register` on door 1 claims the session that door 2's calls then resolve to — so the
model's writes bump the same session's warmth for free. Register once; both doors are that session.

## Install (the human is the arbiter, for now)

Slices before the automated arbiter (pi doc §5, slice 5) install by hand. In the serving funes node's
`iex`, `Funes.MCP.Spawn.env/2` opens a thread, staffs an agent, and prints the identity-only
`export TLON_*` block (`TLON_MCP_URL`, `TLON_THREAD`, `TLON_AUTHOR` — NO `TLON_TOKEN`).
Paste it into a fresh pi pane, then point pi at adapters:

- `~/.pi/agent/settings.json` → `"extensions": [".../modules/adapters/pi/src/extension.ts"]`,
  `"packages": ["pi-mcp-adapter", "npm:pi-sandbox", "npm:@ollama/pi-web-search",
  "npm:pi-agent-browser-native", "npm:pi-multi-account",
  "npm:@gotgenes/pi-permission-system", "npm:pi-cc-header",
  "npm:@lincoln504/pi-research", "npm:pi-interactive-shell"]`,
  `"skills": [".../modules/adapters/skills/*"]`.
- an `mcp.json` (see `pi/mcp.json.example`) points `pi-mcp-adapter` at
  `http://127.0.0.1:${TLON_MCP_PORT}/mcp` with `Authorization` set to a `!command`
  (`scripts/tlon-cli.sh bearer`) that mints a fresh token per connect.

The env contract is identity-only (`TLON_MCP_URL`, `TLON_THREAD`, `TLON_AUTHOR`). The token
is NEVER frozen in env — both doors mint per connect against the URL's `/mint` endpoint, so a
pane survives a funes restart, a token-model change, or a world-secret regeneration (the fix
for the 2026-08-16 literal-tmux stale-401).

## The dev loop

Driven through the shared mise tasks (`mise tasks`), same as the rest of the repo:

- `mise run adapters:pi:test` — the pi adapter's unit suite (`bun test`) — the TDD loop for the brief renderer.
- `mise run adapters:pi:check` — typecheck + tests, the precommit gate for this module.
- `mise run funes:serve` — boot funes with its sovereign channel on, against the scratch db, so a
  hand-spawned pi pane has something to register with.
- `mise run check` — the whole-repo gate (funes + aleph + pi).

## Verify

The proof of the re-brief loop is **seen, not asserted** (pi doc §5, slice 2): boot `funes:serve`,
hand-spawn a pi pane, watch it register and brief; kill it, spawn a fresh one, watch it come up
knowing. The pure renderer is unit-tested (`bun test`); the wiring is proven live.
