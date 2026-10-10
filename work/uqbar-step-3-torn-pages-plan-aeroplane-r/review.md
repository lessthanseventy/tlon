VERDICT: approve — workline A (the aeroplane) only.

Scope: office-only, 6 commits plus plan.md. `kit/plane.ts` (pure flight, freshPosts, handoffFrom), `rooms/wide.ts` (fly/stepPlanes/draw), `tui/main.ts` (feed wiring), AGENTS.md line.

Verified by me: I read the whole diff. `bun test test/plane.test.ts test/uqbar.test.ts` is 27 pass, 0 fail, including the golden-hash-unchanged test. The full-suite green (385 tests) and the server's verify check are the builder's/server's record on the thread; I did not rerun the full suite.

Checked against spec/plan:
- Post: page tears, folds, glides to the lead's desk, else the whiteboard card, else the board edge. Each case tested.
- Hand-off: one flight with a waypoint over the old lead, riding `visits` only while a uqbar session is live. Deviation from the plan's `handoffVia` to `handoffFrom` is sound (the pure kit can't see actor positions).
- Argos catches every 4th plane deterministically; the post still lands, nothing about it changes (fence respected: no dog-ear, no Nina swat).
- First feed load plays nothing; dedupe uses loadFeed's key.

Open, not blocking: workline B (release-cut TV, server surface) is not built; true lead reassignment leaves no server record; the aeroplane is unverified live (no office:drive run). Details in follow_ups.