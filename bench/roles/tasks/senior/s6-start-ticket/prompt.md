Feature: an MCP tool to start a filed ticket.

A filed ticket can be started over HTTP (`POST /api/tickets/:id/start`) and from the CLI, both through
`Server.Tickets.start_thread/2`, which opens a thread on the ticket and promotes the ticket into it
(status `doing`). Coworkers have no MCP tool for it. Add one, test-first, and commit:

- tool name `start_ticket`, registered in the server's tool list right after `update_ticket` and
  before `write_note` (the tool-list test pins the order);
- params: `id` (integer, required, the ticket id) and `agent_id` (integer, optional: hand the new
  thread to that coworker instead of the workspace's lead), passed through to `start_thread/2`;
- on success the JSON result is `{"ticket_id": <id>, "thread_id": <the new thread's id>}`; the new
  thread is titled with the ticket's title and opens with a message from `"andrew"` holding the title
  and body, and the ticket is then `doing`;
- a ticket that doesn't exist is an error result (`isError`) whose text names the id requested.


The project is the Elixir/Phoenix app under `server/` (`cd server && mix test <file>` runs a test file).
