# post_message: a coworker @mentioned on a thread can answer there

Closes #444 and #573.

A peer asked a question on someone else's workline could only answer by relaying through the asker's lead. The mention is now the invitation: `Server.MCP.Tool.may_post?/2` is true when the caller `steers?/2` the thread (lead, parent's lead, manager) or any message on it @mentions the caller. `PostMessage` uses it; `steers?/2` is unchanged for closing and the rest.

- Refusal text now reads "only its lead, or someone @mentioned on it, can act on it from another thread".
- The cross-thread wake text drops `consult_peer` and says: lead or @mentioned → `post_message thread_id: N`, otherwise answer here and @mention the author.

Checked: `menard run test test/server/mcp/server_test.exs test/server/switchboard_test.exs` — red first (4 failures, each on the new text/permission), then 153 tests, 0 failures. New test covers mentioned (succeeds, author = caller) vs. a near-miss handle (`@Carlos`, refused); lead/parent/manager cases untouched.
