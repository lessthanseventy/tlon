# adapters

The hands of the stack. `server` remembers, `office` sees, **`adapters` acts** — it is how a
working agent reaches the server, wakes up already knowing its thread, and banks what it learns.

Every coworker runs in Claude Code, on any model (an ollama one through Claude Code's gateway), and
a **Claude Code mod** — `claude-code/mod.ts`, loaded with `--plugin-dir adapters` — is what makes the
session a citizen of its thread.

## Layout

```
adapters/
  AGENTS.md              the module's law — read it first
  .claude-plugin/        the tlon-citizen plugin's manifest (the plugin root is adapters/)
  hooks/hooks.json       names the mod's hooks module
  claude-code/
    launch.sh            a citizen's window: identity, MCP servers, settings, the mod
    gateway.sh           PROVIDER CMD… — a model's provider as Claude Code's environment
    mod.ts               the mod: presence, brief, capture, wakes, band, commands, tools
    mod.test.ts          its tests, in Claude Code's own kit
    lib/                 its pure helpers, tested with bun (brief, capture, recall, doing, consult)
  lsp/                   the LSP tools as a stdio MCP server, forwarding over a unix socket to…
  lspd/                  …the LSP sidecar daemon that owns the warm language-server pool
  skills/                harness-neutral discipline (a citizen loads them as /tlon-citizen:<name>)
    coordinate-via-funes/  bank-what-you-learn/  keep-todos-current/  verify-with-evidence/  drive-office/
```

## Run it

```
mise run adapters:claude-code:check   # the mod's helpers: install (frozen) + typecheck + tests
mise run adapters:claude-code:mod     # the mod: validate (strict) + its tests in Claude Code's kit
mise run adapters:lsp:check           # the LSP MCP server
mise run adapters:lspd:check          # the LSP daemon
mise run server:claude                # a citizen on the Claude plan
mise run claude:balanced              # …or on an ollama model (also claude:deep / code / fast / local)
```

See `AGENTS.md` for the boundaries every adapter holds to, and `claude-code/README.md` for what the
mod does.
