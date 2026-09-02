# adapters

The hands of the stack. `server` remembers, `console` sees, **`adapters` acts** — it is how a
working agent reaches server, wakes up already knowing its thread, and banks what it learns.

adapters is **vendor-agnostic**: server' channel is MCP, so any harness can be a citizen of a
thread. adapters holds one thin adapter per harness — **`pi/`** (for `pi`, and the models that
run through it — codex, glm, kimi, …) and **`claude-code/`** — plus the pi extensions that are
not server adapters at all (footer, consult, fmt, lsp, reload) but live here because they are
the same kind of thing: TypeScript that pi loads straight from the repo, no build step.

## Layout

```
adapters/
  AGENTS.md            the module's law — read it first
  pi/                  the pi adapter (TypeScript, bun)
    src/extension.ts   pi's lifecycle hooks: register, brief, widget, cadence capture,
                       heartbeat, thinking presence, auto-track
    src/brief.ts       the honest brief renderer (pure, unit-tested)
    src/mcp.ts         a minimal MCP client — the extension's own door to server — and
                       identityFromEnv(), the one parse of the TLON_* identity
    src/capture.ts     delta-slicing, secret redaction, the extraction prompt (pure)
    src/activity.ts    heartbeat cadence + phrasing, commit detection (pure)
    src/recall.ts      correction detection → a proposed habit (pure)
    src/cc-*.ts        the claude-code hook bodies (capture, heartbeat, track, presence),
    src/hook.ts        one bun process per fire, run under hook.ts's ceiling
    src/pi.ts          the slice of pi's ExtensionAPI adapters depends on
    launch.sh          the `pi:*` model launcher — spawns/joins a thread, exports TLON_*
  claude-code/         the Claude Code adapter: launch.sh (`server:claude`) + the
                       SessionStart / UserPromptSubmit / PostToolUse / Stop hook shells
  footer/              a dense 2-line pi statusline — generic, NOT a server adapter
  consult/             /consult and /fresh — delegate a prompt to a different model
  fmt/                 format-on-save for agent-written Elixir files
  lsp/                 the pi shim for the five LSP tools (hover/definition/references/
                       symbols/diagnostics) + `impact`; forwards over a unix socket to…
  lspd/                …the LSP sidecar daemon that owns the warm language-server pool
  reload/              `reload` — respawn pi in place and resume the session
  skills/              harness-neutral discipline (installed into any harness)
    coordinate-via-funes/  bank-what-you-learn/  keep-todos-current/  verify-with-evidence/
```

## Run it

```
mise run adapters:pi:test       # the pi adapter's unit suite (bun)
mise run adapters:pi:check      # install (frozen) + typecheck + tests — the pi package's gate
mise run adapters:consult:check # …and the same gate per package:
mise run adapters:fmt:check
mise run adapters:lsp:check
mise run adapters:lspd:check
mise run adapters:reload:check
mise run adapters:footer:check
mise run adapters:typecheck     # tsc only, every package — the `reload` tool's safety gate
mise run server:serve           # boot server' channel against the scratch db for a hand-run pane
```

The pi-mcp-adapter config (the model's write verbs) is flake-owned: `serverMcpJson` in
`flake.nix` writes `~/.pi/agent/mcp.json` with the `mcpServers.tlon` entry. The extensions and
skills are wired into `~/.pi/agent/settings.json` by the flake's `manosWiring` activation.

See `AGENTS.md` for the two-doors-one-token model, the install, and the boundaries every
adapter holds to.
