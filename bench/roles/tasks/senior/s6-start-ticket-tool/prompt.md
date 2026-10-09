Ticket: `Server.Tickets.start_thread/2` (open a thread on a filed ticket, promote the ticket into it,
move it to `doing`) is reachable from `POST /api/tickets/:id/start` and `tlon-cli ticket-start`, but a
coworker has no MCP tool for it, so they cannot start a ticket themselves. Add an MCP tool
`start_ticket`, wired like the neighbouring ticket tools `file_ticket`, `list_tickets` and
`update_ticket` (`lib/server/mcp/tools/workspace.ex` and the component list in `lib/server/mcp/endpoint.ex`;
register it right after `update_ticket`, the tool list test checks the order).

- params: `id` (integer, required — the ticket id); `agent_id` (integer, optional — hand the new thread
  to this coworker instead of the workspace's lead).
- looks the ticket up first with `Tickets.get/1`; a missing ticket is an error reply whose text names the
  id (e.g. "no ticket #999999"), without calling `start_thread`.
- on success replies `{"ticket_id": <id>, "thread_id": <new thread id>}`; the new thread's opening
  message is the ticket's title and body (what `start_thread/2` already does).

Add tests to `test/server/mcp/server_test.exs`; keep `mix test` green.
