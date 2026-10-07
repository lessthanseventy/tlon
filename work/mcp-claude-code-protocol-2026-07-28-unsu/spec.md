# MCP: Claude Code protocol 2026-07-28 unsupported — anubis_mcp warnings

## Ticket (#1, tertius)

`journalctl --user -u tlon`, over 7 days:
- `MCP transport event: unsupported_protocol_version %{version: "2026-07-28"}` ×19
- `sse_unknown_message %{message: ":read_timeout"}` ×31
- `sse_keepalive_failed` ×23

Bar: a fresh live window shows zero of all three after the fix.

## Diagnosis

### 1. `unsupported_protocol_version` — root cause and blast radius

tlon's server pins `anubis_mcp "~> 2.0"` (`server/mix.exs:126`, locked to `2.0.0` in
`server/mix.lock`). `server/lib/server/mcp/endpoint.ex` does `use Anubis.Server` and never
defines `supported_protocol_versions/0`, so it inherits anubis_mcp's own registry
(`Anubis.Protocol.Registry`, in the dep's `lib/anubis/protocol/registry.ex`), which in 2.0.0
only knows `["2025-11-25", "2025-06-18", "2025-03-26"]`. Claude Code coworkers now negotiate
protocol version `2026-07-28`, which isn't in that map.

Two distinct effects inside anubis_mcp, not one:

- **`initialize` itself does not fail.** `Anubis.Protocol.Registry.negotiate/2` (registry.ex)
  falls back to the server's own latest version when the client's requested version isn't in
  the server's list — the session proceeds, just pinned to `2025-11-25` instead of
  `2026-07-28`. No session is dropped at handshake.
- **Every request *after* initialize is rejected.** Per MCP 2025-06-18+, the client sends the
  protocol version on an `MCP-Protocol-Version` header on each subsequent request. anubis_mcp's
  Streamable HTTP plug (`lib/anubis/server/transport/streamable_http/plug.ex`,
  `validate_protocol_version_header/2`) checks that header against the server's supported list
  and returns **HTTP 400** ("Unsupported MCP-Protocol-Version: ...") when it doesn't match —
  logging exactly the `unsupported_protocol_version` warning we see. Claude Code's client keeps
  sending the version it actually speaks (`2026-07-28`) on that header rather than the older
  version the server negotiated back, so **this is not just noise: each of the 19 is a real
  rejected request**, not a cosmetic log line.

### 2. Is there a fix upstream, or do we patch/pin?

Checked hex.pm directly (`https://hex.pm/api/packages/anubis_mcp`): **anubis_mcp 2.1.0 was
released 2026-10-05**, one day before this ticket was filed. Its CHANGELOG
(github.com/zoedsoupe/anubis-mcp, tag `v2.1.0`) lists, under Features:
- `protocol: add the 2026-07-28 stateless dialect (#269)`
- `server: serve the 2026-07-28 stateless era (#285)`
- `transport: serve the 2026-07-28 stateless era over Streamable HTTP (#307)`

i.e. 2.1.0 adds exactly the version Claude Code is negotiating, on both the server and the
Streamable HTTP transport tlon uses. `server/mix.exs`'s existing `~> 2.0` constraint is already
hex-compatible with `2.1.0` — no `mix.exs` edit needed, no local patch, no need to override
`supported_protocol_versions/0` to pin a version. This is a dependency bump:
`mix deps.update anubis_mcp` (run `--in server` via Menard/mix) + the resulting `mix.lock` diff,
committed.

**Fix for `unsupported_protocol_version`: bump anubis_mcp 2.0.0 → 2.1.0.**

### 3. `sse_unknown_message %{message: ":read_timeout"}` and `sse_keepalive_failed`

Traced in the dep's SSE receive loop (`lib/anubis/sse/streaming.ex`):
- The loop's keepalive ping failing to write to a dead connection logs `sse_keepalive_failed`
  (`handle_message(:sse_keepalive, ...)`).
- Any message the loop doesn't pattern-match falls through to a catch-all that logs
  `sse_unknown_message` with the raw message inspected — `:read_timeout` is not a message
  anubis_mcp's own code ever sends into that loop; it is almost certainly Bandit's own signal
  for an idle long-lived GET socket, which the loop has no clause for.

Two readings, and the evidence doesn't cleanly settle which is right:
- **Separate bug**: an idle-timeout/keepalive interaction in anubis_mcp's SSE loop, independent
  of protocol version, that 2.1.0's changelog gives no indication of touching (its Bug Fixes
  section is about stateless-era progress/header handling, not SSE idle timeouts).
- **Downstream symptom of #1**: if Claude Code treats the 400 on a post-initialize request as
  fatal and tears down/reconnects the session, the SSE GET connection from the old session is
  orphaned; Bandit's idle timeout on that abandoned socket later fires `:read_timeout`, and the
  still-scheduled keepalive ping against it then fails. Counts don't line up 1:1 with the 19
  version-mismatch rejections, but a single severed session can plausibly produce more than one
  stray keepalive tick before Bandit reaps it, so a mismatch in counts doesn't rule this out.

**Decision for this workline's scope** (made here rather than left open, since the ticket's bar
needs all three warnings gone): ship the anubis_mcp 2.1.0 bump, then re-measure a fresh live
window.
- If `sse_unknown_message`/`sse_keepalive_failed` clear along with `unsupported_protocol_version`,
  the downstream-symptom reading was correct and this ticket is done.
- If they persist, they're a separate bug in anubis_mcp's SSE loop and get filed as their own
  ticket rather than blocking this one on a speculative local patch to a dependency we don't own.

## Fix shape

1. `mix deps.update anubis_mcp` in `server/`, committing the `mix.lock` bump to 2.1.0.
2. `mise run server:check` green.
3. `mise run server:release` + `mise run server:restart` to roll the bump onto the live service.
4. Watch `journalctl --user -u tlon` for a fresh window (the next Claude Code MCP sessions
   negotiating) and confirm `unsupported_protocol_version` is gone.
5. If `sse_unknown_message`/`sse_keepalive_failed` are also gone: done, bar met.
   If not: file a new ticket for anubis_mcp's SSE idle-timeout handling; this ticket closes on
   the version-mismatch fix alone, since that's what it was scoped to diagnose and the other two
   are now shown to need separate work.

## Verify

`journalctl --user -u tlon` shows zero `unsupported_protocol_version` events in a fresh live
window after the 2.1.0 bump is released and restarted. (Whether the SSE pair also clears decides
whether this ticket closes alone or spins off a second one — see above.)
