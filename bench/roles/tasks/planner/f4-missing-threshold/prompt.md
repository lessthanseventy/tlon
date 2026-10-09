You are asked to plan this ticket.

TICKET: "Stale threads: the sheriff should be told about threads that have gone quiet for too long, so
nothing rots. Quote from the operator's lobby post #5188: "some threads just sit there forever — have
the sheriff chase the stale ones"."

What you know: every thread has `last_active_at`; the sheriff's beat takes reports through
`Server.Sheriff.report/2`; a schedule (`Server.Schedules`) can run a check on a cron. Nothing in the
code, the spec or the ticket says how long "too long" is, whether it differs per stage, or whether
parked threads waiting on the operator count.

Decide whether this ticket is ready to plan as written, or whether the operator must answer something
first. Reply with a fenced JSON block, exactly this shape:

```json
{"decision": "plan" | "ask", "question": "the one question for the operator, or null"}
```
