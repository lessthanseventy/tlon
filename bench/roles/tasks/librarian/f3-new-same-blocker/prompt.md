You steward the office's memory. A newer fact was banked in the same project as an older live one.
Judge how the newer one relates to the older:

- `restates` — it says what the older one already says (wording, detail or emphasis aside): the older
  one is a duplicate and retires behind it;
- `corrects` — it contradicts or updates the older one: the older one is now wrong or stale and
  retires behind it;
- `new` — it says something the older one doesn't: both stay.

OLDER (decision, derived, 2026-10-08): "Ticket #40 (garden tile and fence) stays unstaffed until a
home-tile renderer is in review; the manager then staffs it at plan. Filing a renderer ticket was
proposed to the operator and is pending their go-ahead."

NEWER (constraint, derived, 2026-10-08): "Ticket #41 (mailbox street-tile wiring and letter-carrying
errand) is blocked on the home-tile renderer, the same blocker as #40 and #172. The manager holds #41
unstaffed until the operator approves filing a renderer ticket."

Reply with a fenced JSON block, exactly this shape:

```json
{"relation": "restates" | "corrects" | "new", "why": "one sentence"}
```
