# #703 — MCP gateway's 30 s request timeout

`drive_smoke` answered "Internal error" on a key list whose `wait:` never matched, yet the keypress
it had sent was consumed. The anubis StreamableHTTP plug defaults to a 30 s request timeout. Past it
the session call exits and the plug answers `:internal_error`, but the tool keeps running, so the
keypress lands anyway.

## What changed

- `Server.MCP.Gateway.init/1` passes `request_timeout: 200_000` to the anubis plug: the drive's 180 s
  wait ceiling plus margin. A one-line comment says why.
- A unit test asserts the plug's `timeout` is 200 000 (RED first: it failed with `timeout: 30000`).

## Ticket

Closes #703.

## How it was checked

- RED: `menard run test --in server test/server/mcp/gateway_test.exs` failed on the new test
  (`timeout: 30000`, the plug default).
- GREEN: the same file, 62 tests, 0 failures.
- Gate: `menard run check --in server`, 2561 tests, 0 failures.

Not yet checked:

- The end-to-end repro on a smoke (`drive_smoke(["wait:NOT-ON-SCREEN"])` returning the screen at about
  33 s) has not been run; it needs the release service.
- Claude Code's own MCP tool timeout and Bandit's HTTP/1 read timeout were not measured. From source,
  Bandit's `read_timeout` (15 s) bounds reading request bytes, not waiting on a response.
- #709 (`run_verb check` from a builder seat) is not claimed fixed by this change.
