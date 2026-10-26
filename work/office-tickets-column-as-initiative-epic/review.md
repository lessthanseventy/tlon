# Review — #616 TICKETS column as initiative → epic → ticket tree

**Verdict: request_changes** — one stale-doc fix, then good to go. Code matches the plan; verify evidence is green (office:check at default/3/15, server office_test 22 ok). I read the diff 611c93d..5018333 and the brief's check records; I did not rerun the suites.

## Blocking
1. `office/AGENTS.md:13` is now false. It says the column shows "one row per epic … children hidden until ⏎ opens the epic". The column is now an expandable tree: ⏎ folds a group's children in place, an in-flight child shows `⚙ on #N` and opens its thread, **space** opens the group's card, and the whiteboard's TICKETS sticky is one line per initiative plus "N loose". Root law: docs change in the same commit as the code. Update that sentence (space, not `o`).

## Non-blocking (follow_ups)
- Wide whiteboard hit tip for the "N loose" sticky reads `#0 3 loose` (wide.ts builds the tip with `#${id}` for every item; only the drawn text special-cases `column`).
- Tree ignores the `who` sort silently (`levelOrder` handles only `title`) while the card title says "by who".
- K/J reorder moves `sel` by ±1 row; with an open group between siblings the cursor lands off the moved ticket. Nested children's reorder semantics unclear.
- Rail column-0 stickies lost the armed/"send to the manager" tip path (`rail.ts:172` is dead for column 0; the TUI passes `armed: null` anyway). Remove or restore on purpose.
