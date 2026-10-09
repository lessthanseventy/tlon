You steward the office's memory. A newer fact was banked in the same project as an older live one.
Judge how the newer one relates to the older:

- `restates` — it says what the older one already says (wording, detail or emphasis aside): the older
  one is a duplicate and retires behind it;
- `corrects` — it contradicts or updates the older one: the older one is now wrong or stale and
  retires behind it;
- `new` — it says something the older one doesn't: both stay.

OLDER (learned, derived, 2026-10-08): "Ticket #75 bug (2026-10-08): Server.Intake.in_flight/1 counts
every todo ticket as in flight, so a todo ticket whose promoted thread closed unmerged (#40 / thread
#179) holds a max_worklines slot indefinitely. start_stalled/1 skips it because it has a promoted
thread. Fix needs a test where a todo ticket's only promoted thread is closed unmerged and
in_flight/1 does not count it."

NEWER (learned, derived, 2026-10-08): "As of 2026-10-08, ticket #75 (thread #200) was started by
intake's 30-minute unstaffed fallback, not by a failure. A coworker leads it at stage build, and the
ticket is doing. The bug it fixes is a closed-unmerged todo ticket holding a max_worklines slot."

Reply with a fenced JSON block, exactly this shape:

```json
{"relation": "restates" | "corrects" | "new", "why": "one sentence"}
```
