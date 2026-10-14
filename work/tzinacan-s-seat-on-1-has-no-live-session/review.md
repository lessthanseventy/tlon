# approve

The fix is correct and minimal. A superseded session latched `superseded` and never polled again,
so once the newer session ended the seat had no live session and wakes went undrained. Now it
keeps calling `take_wakes` each poll: while a newer session holds the seat the server answers
`{superseded: true}` and the mod returns early (said once, takes nothing); when the newer session
is gone the server's `identity.session_id` resolves to nil, `take_wakes` falls through to
`Server.Wake.take` and returns a non-superseded array — the mod clears `superseded`, re-registers,
and resumes.

## verified against the server

`Server.MCP.Tokens.resolve/1` sets `session_id: live_session_id/2` at read time — nil when no live
session holds the pair, never a stale one. `Server.MCP.Tool.TakeWakes.execute/2` returns
`{superseded: true}` only when both `claimed` (the client's session_id) and `identity.session_id`
are integers that differ; a nil `identity.session_id` answers with `Server.Wake.take(...)`, i.e. a
non-superseded array. So the mod's mock sequence (`[gone, [], ["a wake the seat missed"]]`) matches
real behavior: superseded → empty array (recovery trigger) → the missed wake.

## the two tests

The "say so once" guard (`if (superseded) return` before re-submitting) is preserved — the modified
first test asserts one register and one submitted text across three superseded polls. The new test
asserts two registers and the missed wake submitted after recovery. Test-first (red: 1 register,
expected 2 → green), 34 pass.

## one non-blocking observation (no ticket)

Two stale panes for the same seat could both fire `register` in the same poll window before either
holds it — a brief double `start_session`/`supersede_live`. It converges to one holder
(last-writer-wins; the loser's next `take_wakes` sees the winner's session and is told superseded),
and `Server.Orphans` SIGTERMs the old process at spawn, so the duplicate case is rare and
self-resolving. Not worth a follow-up ticket.

Spec compliance: the mod stays a client of the MCP channel (no store writes), holds no retry queue,
and `take_wakes` remains `touch: false` (a clock call is not activity) — all consistent with
`adapters/AGENTS.md`.