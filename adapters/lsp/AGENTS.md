# adapters/lsp — LSP-backed tools for the agent

Gives the agent the same language intelligence the editor has, on demand. Five pi
tools backed by real LSP servers, plus `impact`:

- `hover(path, line, col)` — type/signature/doc at a position
- `definition(path, line, col)` — where a symbol is defined (file:line:col)
- `references(path, line, col)` — where a symbol is referenced
- `symbols(path)` — the document's outline
- `diagnostics(path)` — the server's published errors/warnings (incremental, file-scoped)
- `impact(ref)` — the symbols touched by `git diff <ref>` and their references (`lspd/src/impact.ts`)

`line`/`col` are 1-based (editor convention); the daemon converts to 0-based for the protocol.

## Two packages: the shim and the daemon

This package (`lsp/`) is the **pi shim**: `src/extension.ts` registers the tools and forwards
each call as `{id, method, params}` over a Unix socket (`src/socket.ts`, `LspdClient`) to
**`../lspd`**, the long-lived sidecar daemon that owns the warm language-server pool. The
shim holds no servers: a pi restart leaves Expert warm, and its startup flakiness is paid once
per daemon life, not per pi life. If the daemon isn't reachable the shim spawns it detached and
retries once (`LspdConnectionError`); a daemon that is up but silent is surfaced as a
"restart the daemon" error, never a hang (`LspdTimeoutError`).

The pieces that used to live here now live in `lspd/`:

- `lspd/src/adapters.ts` — the registry of `LanguageAdapter` objects, one per language:
  `{ name, command, args, extensions, rootFor, serverPackage }`. Adding a language is ONE
  object in that array (and usually a package in flake.nix). The shim imports
  `adapterForFile` from there to route a file by extension.
- `lspd/src/client.ts` — the stdio `LspClient`; the daemon keeps one per (adapter, project
  root) for its own lifetime.
- `lspd/src/server.ts` — the socket server + the warm pool; `lspd/src/codec.ts` — the
  length-prefixed JSON framing both sides share.

Current adapters:
- **Elixir — Expert** (`expert --stdio`, expert-lsp.org). The new standard Elixir LSP,
  NOT elixir-ls. Project root: nearest `mix.exs`.
- **TypeScript/JS — typescript-language-server** (wraps tsserver). Root: `tsconfig.json`.
- **Nix — nil**. Root: `flake.nix`.
- **Bash — bash-language-server**. Root: the file's dir.
- **JSON — vscode-json-language-server**. Root: the file's dir.

The servers are flake-managed (`home.packages` in flake.nix) so the next box gets them,
not left to mason or `~/.local/bin`. If a binary is missing, the tool surfaces a clear
"server not found" error — never a hang.

## Law

- **On demand, not on save.** A project-wide compile/typecheck per edit is too heavy;
  menard already formats on save (the pi/extension.ts `tool_result` hook). LSP gives what
  bash+mix can't (type info,
  definitions, references, incremental diagnostics), surfaced when the agent asks.
- **Never hang.** Every LSP request has a timeout (15s default, in `lspd/src/client.ts`);
  the shim's socket request has a longer one, so the daemon always answers first; a dead
  server fails pending requests; a missing binary throws on spawn. The shim turns any
  failure into a tool error string.
- **One client per (adapter, root), owned by the daemon.** LSP servers are long-lived and
  index once per project; reusing them across requests — and across pi restarts — is cheap
  and correct. Clients live for the daemon's life, not the pi session's.
- **typebox is the one external import** (tool param schemas — pi's schema lib, a peer
  dep). Everything else is hand-declared (`src/pi.ts`) or node builtins, the adapters idiom.

## Verify

`mise run adapters:lsp:check` (the shim) and `mise run adapters:lspd:check` (the daemon):
install frozen + typecheck + tests. The shim's tests pin `LspdClient` — forwarding, and the
error taxonomy the self-heal keys on; the daemon's pin adapter routing, root-finding, the
registry's shape, the framing and `impact` — without spawning language servers. Both suites bind real unix sockets,
so they fail under a sandbox that forbids that ("Failed to listen at …sock"); run them
outside it. The stdio `LspClient` is integration: live proof is running a tool against a
real file after `home:switch` (e.g. `hover` on a server `.ex`).