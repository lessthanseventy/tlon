# Uqbar may post on the thread of a need routed to it

Closes #699.

Uqbar's role asks it to tell a seat on its thread what a hook's refusal wants, or that a stalled seat
should advance, then settle the need. `post_message` with that `thread_id` was refused: `may_post?/2`
granted only steering (lead, lead above, manager) and an @mention, and Uqbar is neither on a seat's thread.

`Server.MCP.Tool.may_post?/2` gains a third grant, `routed_to?/2`: the caller is `uqbar` and the thread
has an item in `Server.Office.Needs.grouped/1`'s `uqbar` group. The routed need is the invitation, as the
mention is, and it lapses with the item: settled, passed up, or past `uqbar_route_minutes`. The gate stays
kind-agnostic; the role text in `Server.Profiles` now says to post before settling, and which kind when
(@mention the lead when the seat must act, a notice for an FYI it reads next turn). The refusal names the
new grant, and `server/AGENTS.md`'s `may_post?` line says so.

Checked: two new tests in `server/test/server/mcp/server_test.exs` (a plain post and a notice land on
the routed need's thread; a thread with no need is refused with the new wording; settled, the grant
lapses), red before the change, green after, with the file's 112 tests; `server:check` on the committed
head through `run_task`.
