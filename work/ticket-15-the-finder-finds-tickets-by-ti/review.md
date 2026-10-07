Verdict: APPROVE

Ticket #15 (commit 03b2dca, finder: / finds tickets by title and Enter opens the card).

Checked:
- `ticketPicks` (office/tui/finder.ts) builds ticket rows, matched on `#id title ws`. Enter calls `open({kind:"ticket", id})`, which the `case "ticket"` branch handles.
- `office/test/finder.test.ts` passes 2/2 when run in `office/`.
- No spec/plan in the worktree (operator said none expected), so reviewed against the commit message and brief only.

Notes (not blocking):
1. Thread rows and ticket rows share the `#N` prefix. Typing `#15` lists thread #15 and ticket #15 side by side, distinguishable only by title. Ambiguity, not a bug. Operator's call whether to tag ticket rows.
2. The wiring in `office/tui/main.ts:285` has no test; only `ticketPicks` is covered.