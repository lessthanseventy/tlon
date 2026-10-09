You steward the office's memory. A newer fact was banked in the same project as an older live one.
Judge how the newer one relates to the older:

- `restates` — it says what the older one already says (wording, detail or emphasis aside): the older
  one is a duplicate and retires behind it;
- `corrects` — it contradicts or updates the older one: the older one is now wrong or stale and
  retires behind it;
- `new` — it says something the older one doesn't: both stay.

OLDER (decision, derived, 2026-10-08): "The office test-timeout flake is fixed by office/bunfig.toml,
which sets a 30s test timeout for the whole office suite (commit 1d3b768 on work/t1), instead of
re-running tests. Issue #5 stays open until this lands on main via PR."

NEWER (decision, derived, 2026-10-08): "The office test timeout is PR #100 (20 s in office/bunfig.toml,
auto-merge on). Branches carrying their own timeout line, such as 1d3b768 with 30000, take main's side
when they rebase."

Reply with a fenced JSON block, exactly this shape:

```json
{"relation": "restates" | "corrects" | "new", "why": "one sentence"}
```
