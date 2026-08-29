# adapters/lsp — LSP-backed tools for the agent

Gives the agent the same language intelligence the editor has, on demand. Five pi
tools backed by real LSP servers, spawned per project root and reused for the session:

- `hover(path, line, col)` — type/signature/doc at a position
- `definition(path, line, col)` — where a symbol is defined (file:line:col)
- `references(path, line, col)` — where a symbol is referenced
- `symbols(path)` — the document's outline
- `diagnostics(path)` — the server's published errors/warnings (incremental, file-scoped)

`line`/`col` are 1-based (editor convention); converted to 0-based for the protocol.

## The adapter pattern (the pluggable seam)

`src/adapters.ts` is a registry of `LanguageAdapter` objects — one per language:
`{ name, command, args, extensions, rootFor, serverPackage }`. Adding a language is
ONE object in that array (and usually a package in flake.nix). The extension routes a
file to its adapter by extension; the `LspClient` spawns/reuses the server per
(adapter, project root).

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
  `adapters/fmt` already formats on save. LSP gives what bash+mix can't (type info,
  definitions, references, incremental diagnostics), surfaced when the agent asks.
- **Never hang.** Every LSP request has a timeout (15s default, in `client.ts`); a
  dead server fails pending requests; a missing binary throws on spawn. The extension
  turns any failure into a tool error string.
- **One client per (adapter, root).** LSP servers are long-lived and index once per
  project; reusing them across requests is cheap and correct. Clients live for the pi
  session (no disposal sweep — a pi session is short).
- **typebox is the one external import** (tool param schemas — pi's schema lib, a peer
  dep). Everything else is hand-declared (`src/pi.ts`) or node builtins, the adapters idiom.

## Verify

`mise run adapters:lsp:check` (typecheck + tests). The tests pin the pure seam — adapter
routing, root-finding, the adapter registry's shape — without spawning servers. The
LSP stdio client (`src/client.ts`) is integration: live proof is running a tool against
a real file after `home:switch` (e.g. `hover` on a server `.ex`). The framing
(Content-Length) and request/response correlation are straightforward but only
proven by a live server; a malformed frame is dropped, a timeout fails the request.