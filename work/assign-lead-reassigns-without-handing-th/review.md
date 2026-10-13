# Review: assign_lead hands the leaf over — APPROVE

Branch `work/assign-lead-reassigns-without-handing-th`, commits 7cc8599 + b884fe6. Reviewed by lonnrot.

## Verdict: approve

The change is exactly the ticket's fix (#154): `Server.MCP.Tool.AssignLead.execute/2` now calls
`Server.Staffing.hand_off/2` instead of `Channel.assign_lead/2`. `hand_off` wraps the same
`assign_lead` in a `with`, so the tool's error clauses (`:no_agent`, `:no_thread`, catch-all for
`:manager_leads_no_workline`) still match. A thread with no workspace is a tmux no-op
(`Tmux.run(nil, …)` returns nonzero without calling tmux), so the existing assign_lead test with a
workspace-less thread keeps passing.

## Verified
- `menard run test --in server test/server/mcp/server_test.exs:1097` — 1 test, 0 failures (recorded).
- The test module is `async: false`, so the global `:tmux_cmd` stub is safe; the same stub pattern
  is already used elsewhere in that file. `on_exit` removes it.
- The test asserts the three outcomes the ticket asked for: lead reassigned, `kill-window` on the old
  leaf's index, and the handoff message that wakes the new lead.
- Red-before-green is the builder's claim (emma, #6742); I did not re-run the test against main.

## Findings (non-blocking)
1. `hand_off/2` posts the handoff message as the operator (`:operator`, default "andrew") even when the
   caller is an agent through this tool (tertius, a lead). The thread then records a machine act under
   the human's name. Pre-existing behaviour of `hand_off`, surfaced by this new caller — filed as a
   follow-up, not a blocker.
2. Behaviour change worth knowing, not a bug: a first assignment (no prior leaf) now also posts
   "Handing this to @x", which is what wakes the lead. The moduledoc says so.
