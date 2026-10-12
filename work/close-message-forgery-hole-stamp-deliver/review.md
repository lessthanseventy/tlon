No reviewer at the builder's grade (greybeard) was free, so this review was led by tzinacan at a lower grade.

# Verdict: approve

Scope matches the spec: two surgical changes and nothing else.

## Verified
- `server/test/server/mcp/server_test.exs`: ran unsandboxed, since the sandbox blocks the Postgres socket. Result: `{"ok":true,"tests":68,"failed":0}`. The tool-list assertion includes `get_message`, and the new cross-thread read and not-found tests both pass.
- `Server.MCP.Tool.GetMessage` (`server/lib/server/mcp/tools/reads.ex`): reads `Channel.message/1` (`Repo.get`) and returns a tool error on `nil`. It renders through `MCP.Brief.message/1` plus `thread_id`. The `ok`/`fail` helpers exist in `server/lib/server/mcp/tool.ex`.
- Registered in `server/lib/server/mcp/endpoint.ex` beside `get_messages`.
- `adapters/claude-code/launch.sh`: the header now reads `(message #ID)`, matching `Switchboard.prompt/1`, and the prompt tells the citizen to confirm off-thread notices with `get_message`.

## Notes (non-blocking)
- Cross-thread read is the operator-gated design choice in the spec. It matches `search_history`/`search_facts`, so it opens no new privacy boundary.
- The `launch.sh` change is a prompt string, so only the reading above verifies it, as the spec says.
- The coalesced "you have N unread" drain is the spec's own follow-up and is not touched here.
