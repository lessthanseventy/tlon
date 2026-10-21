Wake-overdue no longer fires falsely on a session waiting on its own background subagent (ticket #532).

- `drainWakes` held `draining` across `$.prompt.submit`, which the host holds until the session is idle, so `take_wakes` never ran again. Submits now run on their own chain; the poll only takes.
- The main `turn.complete` declared `presence_idle` while a subagent still ran. The mod now tracks running subagents (`agentId` on `turn.start`/`turn.complete`) and declares idle only once the main turn and the last subagent have ended; while waiting it refreshes presence every ~3 min against the 600 s stale-turn clock.
- Server guard (`Wake.report_overdue`) unchanged: with presence correct it reads busy.

Checked: `claude plugin test` on the mod (42 pass, incl. two new tests that failed first: a hung submit doesn't stop the next poll from taking; a main turn ending with a subagent running is not idle) and `tsc --noEmit`. Not measured live in a seat; the fix does not depend on whether the host's submit blocks.
