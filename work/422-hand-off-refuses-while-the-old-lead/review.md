No free reviewer is at the builder's grade (senior): this is a mid-grade review by ulrikke, not a senior-level read.

Verdict: approve.

Checked:
- `menard run test --in server test/server/staffing_test.exs`: 44 tests, 0 failures.
- `Staff.end_thread_sessions/1`, `Thinking.stale_turn_seconds/0`, `Channel.thread_lead/1` and the `turn/2` busy check all exist.
- Both callers (operator API `hand_off`, `coordination.ex` `assign_lead`) have catch-all error clauses, so `:lead_mid_turn` cannot crash them.
- The earlier record_check (cmd `true`, event 12055) was a no-op and is void; the real run is event 12057.

Follow-up (non-blocking): the operator sees a bare `:lead_mid_turn` (409 via `inspect`), and the MCP tool says "assign_lead failed: :lead_mid_turn". Give it a readable message.