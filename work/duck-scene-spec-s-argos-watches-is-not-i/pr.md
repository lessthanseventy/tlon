# Name "Argos watches the duck" as skipped in toy step 5's pr.md

Closes ticket #306 (follow-up from #255).

The duck spec says "Argos watches"; `office/kit/events.ts` does not do it. The dog has no existing mode that reads as watching (walk/sit/sleep only), and step 5 reused existing pet modes only, so it was skipped like the zoo's Nina/Argos reactions — but pr.md didn't say so. It now does, deferring to step 7 (cast reacts). Docs-only; no code change.

Checked: diff is one line in `work/toy-step-5-the-events-zoo-meteor-fire-dr/pr.md`; no code or tests touched.
