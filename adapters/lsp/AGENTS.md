# adapters/lsp — LSP-backed tools for the agent

Gives the agent the same language intelligence the editor has, on demand, as MCP tools backed by
real LSP servers:

- `hover(path, line, col)` — type/signature/doc at a position
- `definition(path, line, col)` — where a symbol is defined (file:line:col)
- `references(path, line, col)` — where a symbol is referenced
- `symbols(path)` — the document's outline
- `diagnostics(path)` — the server's published errors/warnings (incremental, file-scoped)
- `impact(ref)` — the symbols touched by `git diff <ref>` and their references (`lspd/src/impact.ts`)

`line`/`col` are 1-based (editor convention); the daemon converts to 0-based for the protocol.

## Two packages: the MCP server and the daemon

This package (`lsp/`) is a **stdio MCP server** (`src/mcp.ts`, newline-delimited JSON-RPC, no SDK):
`adapters/claude-code/launch.sh` wires it into every citizen's `--mcp-config` as `lsp`, so the tools
read as `mcp__lsp__hover` etc. Each call is forwarded as `{id, method, params}` over a Unix socket
(`src/socket.ts`, `LspdClient`) to **`../lspd`**, the long-lived sidecar daemon that owns the warm
language-server pool. The MCP server holds no language servers: a session restart leaves Expert
warm, and its startup flakiness is paid once per daemon life. If the daemon isn't reachable the
server spawns it detached and retries once (`LspdConnectionError`); a daemon that is up but silent
is surfaced as a "restart the daemon" error, never a hang (`LspdTimeoutError`).

In `lspd/`:

- `lspd/src/adapters.ts` — the registry of `LanguageAdapter` objects, one per language:
  `{ name, command, args, extensions, rootFor, serverPackage }`. Adding a language is ONE object in
  that array (and its server in ficciones' flake). `adapterForFile` routes a file by extension.
- `lspd/src/client.ts` — the stdio `LspClient`; the daemon keeps one per (adapter, project root)
  for its own lifetime.
- `lspd/src/server.ts` — the socket server + the warm pool; `lspd/src/codec.ts` — the
  length-prefixed JSON framing both sides share.

Current adapters: **Elixir — Expert** (`expert --stdio`, not elixir-ls; root `mix.exs`),
**TypeScript/JS — typescript-language-server** (root `tsconfig.json`), **Nix — nil** (root
`flake.nix`), **Bash — bash-language-server** (it runs shellcheck), **JSON —
vscode-json-language-server**, **Markdown — marksman**, **TOML — taplo**, **YAML —
yaml-language-server**.

The servers are flake-managed (ficciones `home.packages`) so the next box gets them. A missing
binary surfaces as a clear "server not found" tool error — never a hang.

## Law

- **On demand, plus after each edit.** A project-wide compile/typecheck per edit is too heavy;
  the agent asks for what bash+mix can't give (type info, definitions, references), and the
  tlon-citizen mod attaches a changed file's `diagnostics` to the edit's result.
- **Never hang.** Every LSP request has a timeout (15s default, in `lspd/src/client.ts`); the MCP
  server's socket request has a longer one, so the daemon always answers first; a dead server fails
  pending requests; a missing binary throws on spawn. Any failure becomes a tool error result.
- **One client per (adapter, root), owned by the daemon.** LSP servers are long-lived and index
  once per project; clients live for the daemon's life, not a session's.
- **No dependencies.** The MCP framing is hand-written (`src/mcp.ts`), the rest node builtins.

## Verify

`mise run adapters:lsp:check` (the MCP server) and `mise run adapters:lspd:check` (the daemon):
install frozen + typecheck + tests. The server's tests pin the MCP replies (initialize, tools/list,
a forwarded call, errors as results) and `LspdClient`'s error taxonomy; the daemon's pin adapter
routing, root-finding, the registry's shape, the framing and `impact` — without spawning language
servers. Both suites bind real unix sockets, so they fail under a sandbox that forbids that
("Failed to listen at …sock"); run them outside it. Live proof is a tool call against a real file
from a citizen session (e.g. `mcp__lsp__hover` on a server `.ex`).
