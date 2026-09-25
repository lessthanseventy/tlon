# adapters — the hands

The third story in the stack. `server` is the memory, `console` is the sight, `adapters` is the
**hands**: how a working agent reaches server, comes up already knowing its thread, and banks what it
learns as it works. Read `../server/docs/spec.md` and
`../../docs/plans/2026-08-15-pi-integration-and-server-mcp-design.md` before reshaping anything here —
this module is Track B's agent side, and the spec's boundaries govern it.

## What adapters is, and is not

**adapters is vendor-agnostic by identity.** the server's channel is MCP — an agent-agnostic protocol, not a
pi API — so *any* harness can be a citizen of a thread. adapters holds **one adapter per harness**, each
a thin bridge from that harness's lifecycle to the server's one sovereign channel:

- **`pi/`** — the pi adapter (built). A TypeScript extension for `pi`
  (`github.com/earendil-works/pi`): `extension.ts` registers at session start, briefs before the
  agent runs, and shows server state in the widget. pi is the harness for codex / glm / kimi / any
  model that speaks it.
- **`footer/`** — a dense 2-line pi statusline (full model name, context bar, I/O, branch,
  statuses). NOT a server adapter — a generic footer, kept in its own package so a self-contained
  coworker (the Tlön profile drops `adapters/pi` to sever server) still gets it. It reads pi's own
  model/context/session surface, not server.
- **`claude-code/`** — the Claude Code adapter (built). Same two doors, adapted to Claude Code's own
  mechanisms: the MCP tools via `mcpServers.tlon` `type:http` with a **`headersHelper`**
  (`scripts/tlon-cli.sh token`) that mints a FRESH token per connect — so unlike pi's static bearer,
  auth survives a server restart — and the brief via a `SessionStart` hook (`brief-hook.sh`). Both are
  scoped to the session by `server:claude`'s `--mcp-config`/`--settings` launch flags, so a plain
  `claude` is untouched and nothing is merged into `~/.claude`. See `claude-code/README.md`.

**The rules that hold across every adapter — break one and adapters stops being the hands:**

- **An adapter is a client of the server's MCP channel, never a second writer.** It calls the channel; it
  never touches the shared SQLite. A direct write bypasses the server's single-writer + Bus-announce
  discipline (spec §4/§10) — the drift the whole stack is built against.
- **An adapter holds no state.** No retry queue, no spill file. When server is unreachable it surfaces
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

An adapter reaches server through **two MCP connections that share one bearer token**, and the token —
not the transport — is the identity:

1. **The extension's own client** calls `register` (once, at session start) and `get_dossier` (to
   brief), deterministically, before the model runs. There is no pi API to invoke a tool from a hook,
   so the extension is itself a small MCP client (`pi/src/mcp.ts`).
2. **`pi-mcp-adapter`** exposes the server's write verbs (`post_message`, `bank_fact`, `raise_issue`,
   `record_done`) to the *model* as first-class tools.

Because the server resolves every call's identity from the **token** (`Server.MCP.Tokens.resolve/1` — a
stateless signed claim on thread + agent), not from a transport connection, `register` on door 1 claims the session that door 2's calls then resolve to — so the
model's writes bump the same session's warmth for free. Register once; both doors are that session.

## Install

The launchers do the spawn: `mise run pi:*` (`pi/launch.sh`) and `mise run server:claude`
(`claude-code/launch.sh`) call `scripts/tlon-cli.sh spawn`, which opens (or `--join`s) a thread,
staffs the agent, and exports the identity-only `TLON_*` block (`TLON_MCP_URL`, `TLON_THREAD`,
`TLON_AUTHOR` — NO `TLON_TOKEN`) before exec'ing the harness. The same block is what
`mise run server:spawn` prints for a hand-run pane.

pi's side is flake-owned (`manosWiring` in `flake.nix`, applied by `home:switch`) — it merges
into `~/.pi/agent/settings.json`:

- `"extensions"`: the six repo extensions — `pi/src/extension.ts`, `consult/src/extension.ts`,
  `lsp/src/extension.ts`, `reload/src/extension.ts`, `footer/src/footer.ts`, and menard's
  `pi/extension.ts` (shipped from ~/projects/menard, wired here by the flake).
- `"packages"`: `["npm:pi-mcp-adapter", "npm:pi-sandbox", "npm:@ollama/pi-web-search",
  "npm:pi-agent-browser-native", "npm:pi-multi-account", "npm:@gotgenes/pi-permission-system",
  "npm:@lincoln504/pi-research", "npm:pi-interactive-shell", "npm:@narumitw/pi-retry",
  "npm:@pi-unipi/notify"]` (pi-cc-header was retired; the flake prunes it).
- `"skills"`: `".../modules/adapters/skills/*"`.
- `~/.pi/agent/mcp.json` is flake-owned (`serverMcpJson` in `flake.nix`): its `mcpServers.tlon`
  entry points `pi-mcp-adapter` at `${TLON_MCP_URL}` with `Authorization` set to a `!command`
  (`scripts/tlon-cli.sh bearer`) that mints a fresh token per connect. There is no example
  file to copy — the flake is the config.

The env contract is identity-only (`TLON_MCP_URL`, `TLON_THREAD`, `TLON_AUTHOR`). The token
is NEVER frozen in env — both doors mint per connect against the URL's `/mint` endpoint, so a
pane survives a server restart, a token-model change, or a world-secret regeneration (the fix
for the 2026-08-16 literal-tmux stale-401).

## The dev loop

Driven through the shared mise tasks (`mise tasks`), same as the rest of the repo:

- `mise run adapters:pi:test` — the pi adapter's unit suite (`bun test`) — the TDD loop for the brief renderer.
- `mise run adapters:pi:check` — typecheck + tests, the precommit gate for this module.
- `mise run server:serve` — boot server with its sovereign channel on, against the scratch db, so a
  hand-spawned pi pane has something to register with.
- `mise run check` — the whole-repo gate: `server:check`, `console:check`, and the six
  adapters packages (`adapters:{pi,consult,lsp,lspd,reload,footer}:check`). menard's pi adapter
  is checked in its own repo (its `test` task, in ~/projects/menard).

## Verify

The proof of the re-brief loop is **seen, not asserted** (pi doc §5, slice 2): boot `server:serve`,
hand-spawn a pi pane, watch it register and brief; kill it, spawn a fresh one, watch it come up
knowing. The pure renderer is unit-tested (`bun test`); the wiring is proven live.
