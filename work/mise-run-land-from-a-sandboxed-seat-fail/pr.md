# land_pr: queue a reviewed PR over MCP, so a sandboxed seat can land (closes #634)

`mise run land` ends in `bin/server rpc`, which needs epmd; a seat's bwrap sandbox refuses loopback, so
every reviewing seat got `:noconnection` and had to ask the operator to land for it.

- `Server.PRLanding.request/3`: `scripts/land.sh`'s gh preflight (open, onto main, not a fork, not main,
  not protected) run server-side, then the existing `queue/4`. Same refusals, same queue.
- `land_pr(pr)` MCP tool over it (`Server.MCP.Tool.LandPR`). `land.sh` is unchanged for the host.
- AGENTS.md says a sandboxed seat uses the tool.

Checked: `pr_landing_test.exs` (request/3 queued + the six refusals, red first), `mcp/server_test.exs`
(tool list). Full gate: run_task check on the head.
