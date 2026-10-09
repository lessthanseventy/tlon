You are asked to plan this ticket.

TICKET: "`mise run server:roster` prints coworkers in hire order; sort it by name instead (case-
insensitive), so a seat is easy to find. Acceptance: `server:roster` with seats `zunz`, `Emma`,
`pierre` lists Emma, pierre, zunz. Quote from the operator's lobby post #5202: "the roster is in a
random order, sort it by name please"."

What you know: the roster comes from `Server.Staff.roster/0` (`server/lib/server/staff.ex`), which
orders by `agent.inserted_at`; `scripts/tlon-cli.sh` prints whatever it returns. Nothing else reads
its order.

Decide whether this ticket is ready to plan as written, or whether the operator must answer something
first. Reply with a fenced JSON block, exactly this shape:

```json
{"decision": "plan" | "ask", "question": "the one question for the operator, or null"}
```
