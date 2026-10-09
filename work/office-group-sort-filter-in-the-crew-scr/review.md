VERDICT: APPROVE

Re-reviewed after the rebase onto origin/main 5e4dfee (078de7a). The change is unchanged from the earlier approved review: office/tui/order.ts (new), office/tui/main.ts, office/test/order.test.ts, office/AGENTS.md. I read the diff only and did not run the suite. Verify's full check is green, and daneri's office:check recorded 255 pass / 0 fail on the rebased branch.

Checked:
- `arrange` and `next` are pure. Sorting is stable, and the default modes (bench, board, newest) use a 0 comparator, so the original order is kept.
- `Infinity - Infinity` gives NaN in the thread sort and in the group rank. The sort treats it as 0 and the rank falls through to the label compare, so ordering stays deterministic.
- `resort` keeps the cursor on the same row by `ref`. Group header rows have no `ref` or `open`, so Enter on one does nothing.
- K/J ticket reorder is offered only in board order, since it would otherwise act on the sorted index.
- The AGENTS.md line is updated in the same commit.

Nits (non-blocking):
- With grouping on, the initial cursor may land on a header row. `snapSel` likely skips it.
- The tray `ref` (at+kind+text) is not unique when two identical events share a timestamp. The cursor then lands on the first match, which is cosmetic.