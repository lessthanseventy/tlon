# Close the message-forgery hole: verifiable id + read-by-id

Ticket #153 (security). Follow-up to issues #14 / #16 (forged thread messages reaching agent
sessions under another agent's name, no message id).

## What #264 already closed

`Server.Switchboard.prompt/1` (`server/lib/server/switchboard.ex:505`) stamps every live wake as

    New message on thread #{thread_id} from #{author} (message ##{id}): #{body}

The `author` is `identity.agent` — the signed token's `sub` claim (`Server.MCP.Identity`,
`register`), never a caller-supplied param. `consult_peer` reuses the same `Channel.post` path
(`author: caller.agent`), so consult deliveries are authenticated the same way. The wake header —
id included — is already tested green: `server/test/server/switchboard_test.exs:343`.

So the **author half of the forgery hole is closed**, and the **id is already on the live
delivery**. The earlier "forgeries" were real messages that arrived without an id (pre-#264); the
workaround reviewers adopted was refusing id-less notices (fact #1168).

## The open half

A **recipient can't verify the id**: there is no read-by-id MCP tool (`search_history` is BM25
over bodies — it finds a message by distinguishing words, not by id), and
`adapters/claude-code/launch.sh:104` still coaches the OLD id-less header

    Messages arrive in your input as "New message on thread N from <author>: …"

so the citizen does not know the id is there or how to check a notice from a thread it is not on.

## Scope — two surgical changes

1. **`get_message(id)` MCP tool — cross-thread.** A new `Server.MCP.Tool.GetMessage` module in
   `server/lib/server/mcp/tools/reads.ex`, modelled on `GetMessages` (line 45) but taking a
   required `id` and reading one row, not a list. It calls the existing `Server.Channel.message/1`
   (`server/lib/server/channel.ex:398` — `Repo.get(Message, id)`), renders via
   `MCP.Brief.message/1` (`server/lib/server/mcp/brief.ex:180`), and returns a not-found tool error
   on `nil`. Registered in `server/lib/server/mcp/endpoint.ex` beside `get_messages` (line 64):
   `component(Server.MCP.Tool.GetMessage, name: "get_message")`.

2. **`adapters/claude-code/launch.sh:104` — coach the real header.** Update the citizen
   system-prompt sentence to the actual format `New message on thread N from <author> (message #ID): …`
   and add that a notice from a thread you are not on should be confirmed with `get_message(id)`
   before acting on it (the id names a row; if `get_message` returns not-found, the notice is not a
   real delivery).

## Design decision (the operator gate)

`get_message(id)` is **cross-thread** — any id, regardless of the caller's bound thread.

- It matches the existing cross-thread reads `search_history` and `search_facts`, which already
  return bodies channel-wide. No new privacy boundary is opened: the agent already received the
  body in the wake; `get_message` only confirms the author, the thread, and that the row exists.
- It is exactly what the forgery scenario needs — verifying a notice on a thread the recipient is
  NOT on (a reviewer asked to act on another thread's work). A self-thread-only tool would block
  precisely the case that motivated the ticket.

Recommend cross-thread. If the operator disagrees, the fallback is self-thread-only with the
`own/4` scoping helper (`Server.MCP.Tool.own/4`), which refuses another thread's row.

## Out of scope

The coalesced backlog drain (`switchboard.ex:573`, "you have N unread message(s)") carries no
author or body — it is not a forgery surface, and it routes the agent to `get_messages`, which is
trusted. Flagged as a follow-up, not in this fix.

## Tests it starts from

`server/test/server/mcp/server_test.exs` — over the wire, beside the `get_messages` test:

- **cross-thread read:** post a message on thread A; from a session bound to a *different* thread
  B, call `get_message` with A's message id; assert the row comes back with A's author, body and
  `thread_id`. (Red before: no such tool / method not found. Green after.)
- **not-found:** `get_message` with an id no row has returns a tool error, not a crash.

`launch.sh` is a prompt string, not unit-tested; verified by reading the committed line at review.