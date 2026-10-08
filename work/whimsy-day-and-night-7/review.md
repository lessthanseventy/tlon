APPROVE — whimsy-day-and-night-7 @ 813179f (rebased onto main)

I read the full office diff. daylight.ts hours match the windows' sky; the dim is painted last, below the windows band; all three lamps (lounge, manager, lead) register before nightfall runs, and a wide test asserts that. Pets only turn in when idle. There is one `dark` predicate. The existing zoomies and antics tests are pinned to daytime, so they don't flake after dark. Goldens were re-hashed after the rebase. Server verify (mise run check) passed per recorded evidence.

Verified by me: `bun test test/daylight.test.ts test/wide.test.ts` in office/ gives 29 pass, 0 fail under both OFFICE_TEST_HOUR=3 and 15.

Not verified: the full suite, and the live render.

Process note: intent/spec/plan are not committed on the branch, so the merge proof shows them missing. That is the operator's call at the gate. The merge queue also bounces if the main checkout is dirty.