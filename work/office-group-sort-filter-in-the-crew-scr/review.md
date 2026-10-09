VERDICT: APPROVE

Reviewed fefad60 against main: office/tui/order.ts (new), office/tui/main.ts, office/test/order.test.ts, office/AGENTS.md. Read the diff only; I did not run the suite. Verify's full check is green, and daneri's unsandboxed office:check recorded 249 pass / 0 fail.

Checked:
- Sort/group is pure (`arrange` / `next`). Sorting is stable, and the default "bench" / "newest" / "board" modes use a 0 comparator, so the original order is kept.
- The `Infinity - Infinity` NaN in the thread sorts is treated as 0 by `Array.prototype.sort`, so the comparator is safe.
- Group rank: status order is waiting, working, idle. Thread groups sort by id with "on the bench" last. Ties fall back to label.
- `resort` keeps the cursor on the same row by `ref` (crew name, the JSON of a column item's act, or at+kind+text for the tray). Header rows carry no `ref` or `open`, so Enter on one does nothing and `seatActions(undefined)` matches the old empty-selection behaviour.
- K/J ticket reorder is offered only in board order, because it would act on the sorted index otherwise. This is correct.
- The AGENTS.md line is updated in the same commit, as the repo law requires. The tests cover the sort and group modes.

Nits (non-blocking):
- With grouping on, the initial cursor (sel=0) lands on the first header row. Not harmful, and the existing snapSel may already skip it.
- The tray `ref` is not unique if two identical events share a timestamp; the cursor then lands on the first match. Cosmetic.