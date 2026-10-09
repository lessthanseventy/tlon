You steward the office's memory. A newer fact was banked in the same project as an older live one.
Judge how the newer one relates to the older:

- `restates` — it says what the older one already says (wording, detail or emphasis aside): the older
  one is a duplicate and retires behind it;
- `corrects` — it contradicts or updates the older one: the older one is now wrong or stale and
  retires behind it;
- `new` — it says something the older one doesn't: both stay.

OLDER (learned, derived, 2026-10-08): "A coworker's original north-wall suggestion text is not
retrievable through search_history; only the approval posts are searchable, so the exact ask must come
from the requester or the operator."

NEWER (constraint, derived, 2026-10-08): "The coworker's original north-wall suggestion text cannot be
recovered via search_history; only the approval posts (#4047, #4055) are searchable, so the exact ask
must come from the requester or operator."

Reply with a fenced JSON block, exactly this shape:

```json
{"relation": "restates" | "corrects" | "new", "why": "one sentence"}
```
