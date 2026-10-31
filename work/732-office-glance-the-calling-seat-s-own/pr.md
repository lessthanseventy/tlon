office_glance: a seat sees its own row as `me` (#732)

`crew` is the other seats by design (the mod's band and `@`/`#` completion read it), so the caller could not check its own presence over MCP. The glance now carries `me`, the caller's roster row (same shape as a crew entry); `crew` is unchanged.

Checked: new test in `server/test/server/mcp/server_test.exs` (presence_doing("bash") then office_glance → `me.doing == "bash"`, caller absent from `crew`) red on `me` nil, green after; the file's 110 tests pass via `menard run test --in server`.

Closes #732.
