The rack card (H) painted a node with no job queue as a red `✕` row under a "THE RACK · all green" header. A smoke node runs without Oban by design and the server rightly calls it ok, so the card contradicted itself.

`jobs: false` now renders as a dim neutral `○ no job queue on this node`; the header and the server are untouched. Closes #550.

Checked: `office/test/rack-card.test.ts` gained a case (jobs false, no problems) asserting the header reads "all green", no `✕` is on screen, and the line carries the dim colour. It failed on the `✕` before the change; `bun test test/rack-card.test.ts test/rack.test.ts` is 7 pass, 0 fail after.

The office gate (`office:check`) also typechecks the test, so the no-job-queue fixture's `checks.running: null` now goes through `as unknown as typeof health` (TS2352 otherwise; assertions untouched). `bun run typecheck` and `bun test test/rack-card.test.ts test/rack.test.ts` are green on that commit.
