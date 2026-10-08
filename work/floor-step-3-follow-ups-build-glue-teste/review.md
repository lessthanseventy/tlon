# Review — floor-step-3 follow-ups: APPROVE

Read the rebased diff against origin/main (office/kit/home.ts, tui/home.ts, tui/main.ts, test/home.test.ts). I did not re-run tests; the server's VERIFY recorded `mise run check` green on this branch.

- **applyBuild**: same logic as the inline glue it replaces (save only when `writes` changed), injectable `save`, spy-tested for move/pick-up/refused drop/successful drop/place/undo. main.ts is a clean swap.
- **rot kept**: `place` carries `existing.rot` when cycling the kind; rot 0/undefined falls to the plain tile, equivalent. Test covers 90. Not drawn in the grid, so unit test is the only evidence.
- **gridWindow/GRID_MAX**: under the cap it is the old tiles+cursor+margin box; over it, a window of exactly GRID_MAX centred on the cursor, so the cursor is always inside. Test covers far cursors on both axes.

Nits, not blocking:
- When the window is clamped, tiles outside it are not drawn, with no indicator. Acceptable for a cap.
- The rebased branch is not yet force-pushed; that is the human's call.
