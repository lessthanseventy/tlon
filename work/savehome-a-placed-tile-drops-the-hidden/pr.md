Closes ticket #140 — saveHome kept a hidden unknown-kind tile on a cell a known tile was placed on, so home.json could hold two tiles at one `at`.

**Why.** Follow-up from #233 (loadHome carries unknown tile kinds opaque). When the unknown kind returned, loadHome showed both tiles on one cell. Decision (tertius, from Andrew's ticket): the placed known tile wins.

**What.** `saveHome` (office/tui/home.ts) drops a hidden unknown-kind tile whose `at` collides with a known tile in the home being saved. Hidden tiles on free cells are still carried through load/save unchanged.

**Checked.** RED first: the new test failed with the hidden tile at [1,0] kept beside the kitchen. GREEN: `bun test test/home.test.ts` 28 pass, 0 fail. `bun run typecheck` exit 0. Full office suite `OFFICE_TEST_HOUR=3 bun test` and `OFFICE_TEST_HOUR=15 bun test`: 624 pass, 0 fail each.
