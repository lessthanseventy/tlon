You steward the office's memory. A newer fact was banked in the same project as an older live one.
Judge how the newer one relates to the older:

- `restates` — it says what the older one already says (wording, detail or emphasis aside): the older
  one is a duplicate and retires behind it;
- `corrects` — it contradicts or updates the older one: the older one is now wrong or stale and
  retires behind it;
- `new` — it says something the older one doesn't: both stay.

OLDER (learned, derived, 2026-10-07): "Isolated test runs need a primed build and scrubbed
CLAUDECODE/nested-Claude-Code env vars, otherwise cold _build cache and env contamination produce false
failures (8 bogus failures seen once)."

NEWER (learned, derived, 2026-10-07): "Isolated test runs must use a primed _build and a scrubbed
CLAUDECODE/nested-Claude-Code env; otherwise a cold cache and env contamination produce false failures,
as in the 7 bogus failures a coworker saw on #140."

Reply with a fenced JSON block, exactly this shape:

```json
{"relation": "restates" | "corrects" | "new", "why": "one sentence"}
```
