Close a workline settled without code with a third why: `resolved`

A workline finished as "upstream-only / no code" could only close as `abandoned`, which re-queues its ticket to intake, so the same ticket was triaged twice (#464 / workline 414).

- `Channel.close_as/2` accepts `{:resolved, why}`; `Tickets.closed_unmerged/3` marks the ticket done and appends "Resolved without code in workline #N: why".
- `resolved` is exposed beside `superseded_by` / `abandoned` in `finish`, `close_thread`, the operator API close and `tlon-cli close-thread`.

Closes #707.

Checked: new RED tests (`tickets_test`, `finish` in `mcp/server_test`) failed first, now green; `menard run check --in server`: 2562 tests, 0 failed.
