# Hall look card: say where the look goes

In the hiring hall, `e` on a slot row opens the look card, whose first line said "look at the room — a saved change shows there live, with no restart". A candidate who isn't hired yet isn't in the room, and `_` in hall mode keeps the look on the candidate and writes it to `looks.json` at hire, so the line was wrong there.

The hint now comes from `lookHint(hall)` in `office/tui/hall.ts`: hall mode says the look is kept on the candidate until they're hired; room mode keeps the old line. `main.ts`'s `case "look"` calls it.

Closes #663.

## How it was checked

- Test first: `office/test/hall-view.test.ts` imports `lookHint`, and the run went red with "Export named 'lookHint' not found". After the change it passes, 6/6.
- `mise run office:check`: typecheck clean, 965 tests pass with 0 fail at `OFFICE_TEST_HOUR=3` and `=15`, exit 0.
