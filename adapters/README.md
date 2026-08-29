# adapters

The hands of the stack. `funes` remembers, `aleph` sees, **`adapters` acts** — it is how a
working agent reaches funes, wakes up already knowing its thread, and banks what it learns.

adapters is **vendor-agnostic**: funes' channel is MCP, so any harness can be a citizen of a
thread. adapters holds one thin adapter per harness. Today that is **`pi/`** (for `pi`, and
the models that run through it — codex, glm, kimi, …). Claude Code is a first-class harness
too; its adapter is born when it has content, not before.

## Layout

```
adapters/
  AGENTS.md              the module's law — read it first
  pi/                    the pi adapter (TypeScript)
    src/extension.ts     register + brief + footer, via pi's lifecycle hooks
    src/brief.ts         the honest brief renderer (pure, unit-tested)
    src/mcp.ts           a minimal MCP client — the extension's own door to funes
    src/pi.ts            the slice of pi's ExtensionAPI adapters depends on
    mcp.json.example     the pi-mcp-adapter config (the model's write verbs)
  skills/                harness-neutral discipline (installed into any harness)
    coordinate-via-funes/
    bank-what-you-learn/
```

## Run it

```
mise run adapters:pi:test   # the renderer's unit suite (bun)
mise run adapters:pi:check  # typecheck + tests — this module's gate
mise run funes:serve # boot funes' channel; in its iex, Funes.MCP.Spawn.env/2 prints the
                     # export TLON_* block to paste into a fresh pi pane
```

See `AGENTS.md` for the two-doors-one-token model, the install, and the boundaries every
adapter holds to.
