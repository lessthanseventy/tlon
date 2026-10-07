APPROVE

## Scope
Commit 4c2242f adds `start_ticket` MCP tool: `server/lib/server/mcp/endpoint.ex` (registration), `server/lib/server/mcp/tools/workspace.ex` (`Server.MCP.Tool.StartTicket`), `server/test/server/mcp/server_test.exs` (2 new tests + tool-listing assertion). No spec.md/plan.md exist for this workline — expected, since it started after those stages.

## Spec compliance
Goal: "MCP tool to start a filed ticket." Delivered via the same door as the existing API/CLI path (`Server.Tickets.start_thread/2`), matching the file/list/update_ticket tools already wired the same way. `id` is looked up first and a missing ticket is refused before calling into `Tickets`, matching `UpdateTicket`'s pattern exactly. `agent_id` is optional, defaulting (via `start_thread/2`'s own default) to the workspace lead. Meets the ask.

## Correctness
- `Tickets.get/1` → `nil` → `fail(frame, "no ticket ##{id}")`, else `reply/3` over `Tickets.start_thread(ticket, params[:agent_id])`, rendering `%{"ticket_id" => ticket.id, "thread_id" => thread.id}`. Consistent with `reply/3`'s `{:ok, row} | {:error, _}` contract in `Server.MCP.Tool`.
- `start_thread/2` already handles `agent_id: nil` (defaults to no `:agent_id` key passed to `open_thread`), so the tool doesn't need to special-case it.
- Endpoint registration is placed correctly in the "container tier" ticket block.
- Test `start_ticket refuses a missing ticket` checks the error text contains the id — matches `fail`'s message format.

## Verification
Ran the test file directly (not just trusting the builder's report): `menard run test --in server test/server/mcp/server_test.exs` → `{"ok":true,"tests":34,"failed":0,"failures":[]}`. All pass, including both new `start_ticket` tests.

Builder (daneri) reported a pre-existing unrelated `commits_test.exs` failure in the full `server:check` run, reproducing with this diff stashed out too — not this change's fault, and out of scope for this ticket's review; didn't re-verify that claim since it's orthogonal to the diff under review.

## Findings
None. No security concerns (no new external input paths beyond the existing `id`/`agent_id` integer schema fields, same shape as `update_ticket`). No scope/ownership check on the ticket's workspace, but that matches `UpdateTicket`'s existing behavior — not a regression introduced here.
