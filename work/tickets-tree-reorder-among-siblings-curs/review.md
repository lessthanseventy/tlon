APPROVE. Right then, read the diff (origin/main...HEAD, 4 commits); did not re-run the gates.

- `Tickets.neighbour/2`: scoping to same status + same epic is correct. Loose tickets use `not in` the parent-link targets, and children use `in` the epic's children. `epic_of/1` is a `Repo.one`, which is safe because the DB guards a single parent. The new test covers both directions: a child never trades with a loose ticket or another epic's child, and a top-level ticket trades with an epic.
- TUI: the cursor now lands on the row whose `ref` equals `JSON.stringify(it.act)`. That is the same encoding the rows are built with at main.ts:1336 and :1343. The fallback to the old one-row step is kept.
- Dead code: removing the rail's ticket sticky branch together with `Focus.armed` is clean, and every test and call site that used `armed` is updated.
- `tree-reorder.test.ts` drives the real TUI against a stub server.
- `pr.md` sits at `work/<slug>/pr.md`, like the other worklines'.

Evidence limits: I did not verify the claimed 36 server tests or the office 962; the verify gate runs the full suite.