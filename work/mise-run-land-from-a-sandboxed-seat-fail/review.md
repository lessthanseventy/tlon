# Review: land_pr over MCP (work/mise-run-land-from-a-sandboxed-seat-fail @ 55952bd)

**Verdict: approve.**

The change does what ticket #634 asks: a seat whose sandbox has no epmd hands a reviewed PR to the same merge queue through an MCP tool instead of `mise run land`. Two commits, 139 lines, nothing outside the ask.

## What I verified

1. **The preflight is land.sh's, clause for clause.** `request/3` reads the same five gh fields, refuses in the same order with the same wording (closed, not onto main, fork, head is main, protected, unreadable), then calls the existing `queue/4` with the branch and author exactly as `tlon-cli land-pr <pr> <head> <author>` would. The real gate (an independent approving review at the head, `BranchReview.approves/4`) is unchanged and still runs inside `queue/4`, so the tool opens no new door: a builder calling it on its own PR is refused the way the host shell is.
2. **The tool reaches the seat that needs it.** `land_pr` is in no profile's `excludeTools` (`Server.Profiles`, base list at profiles.ex:324 and the reviewer/QA/PM/librarian deltas), so a reviewer seat gets it. The tool-list test in `mcp/server_test.exs` pins that.
3. **Tests.** `menard run test --in server test/server/pr_landing_test.exs` → `{"ok":true,"tests":13,"failed":0}`. The two new tests cover the queued path and all six refusals with `jobs() == []` after. The server's own `mise run check` passed on 55952bd (brief, 2026-10-26 09:41Z).
4. **Errors from the tool are strings, never crashes.** Every `{:error, _}` out of `request/3` is a binary, so `fail/2` renders it; the `inspect` fallback is for `queue/4`'s enqueue errors.
5. **Docs.** Root AGENTS.md names the tool next to `mise run land`. No profile prose tells a seat to run `mise run land` (grepped server/lib); the brief that did was the ticket's own text.

## Not blocking (follow_ups)

- `stderr_to_stdout: true` on the two parsed gh calls diverges from land.sh's `2>/dev/null`: any stderr line on exit 0 breaks the JSON decode and the exact `"false"` match. See follow-ups.
- The queue post names the approver but not who queued it; the frame's identity is at hand.

Branch sits behind origin/main by the TICKETS-column work; the merge gate rebases, no conflict expected (disjoint files).
