assign_lead hands the leaf over

`Server.MCP.Tool.AssignLead` called `Channel.assign_lead/2` alone, so the old lead's leaf window
stayed on the thread and the new lead could not be spawned onto it (`:already_running`). The tool now
goes through `Server.Staffing.hand_off/2` like the office, `Workline.hand_to/4` and `escalate/2`: it
reassigns, closes the stale leaf and posts the handoff that wakes the new lead.

Closes ticket #154.

Checked: new test in `server/test/server/mcp/server_test.exs` (old lead's leaf window is killed, new
lead is woken) went red first; `menard run check --in server` green, 1578 tests, 0 failures.
