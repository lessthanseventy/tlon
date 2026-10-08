REQUEST_CHANGES — supersedes my earlier approve. The grader's two points both check out against the branch, and I missed them.

1. Fuss/scuffle guard (office/rooms/wide.ts, step()). The paper trigger checks only `!dog.path.length`, mode, `quiet`. stepDog's own idle roll also requires `!d.fuss` and returns early on `ctx.antic` (pets.ts:148-149). Without those, Argos can be sent to the office mid-fuss or mid-scuffle. Fix: add `!this.antic && !this.dog.fuss` to the paper guard.
2. Unrelated files on the branch. `git diff main...HEAD` includes review.md for floor-step-3-follow-ups-build-glue-teste, whimsy-birthdays-from-the-calendar-7 and whimsy-day-and-night-7 (the last records request_changes). They are other worklines' workline commits (3dbc2a4, d254dc5, 1092b15, ccba074, 20abd54), outside this PR's scope. They must not ride in on this PR. Rebase them out (or confirm they are already on main and the branch just needs a rebase onto current main), per the repo's linear-history rule.
3. Note the else-if reorder of the muse chime in the commit message as a deliberate departure from the plan. It is needed, since otherwise muse speaking makes `quiet` false and paper never fires in the test.
4. Optional: add a test that muse still fires when the paper roll misses.

Everything else stands: the paper lines, the dogDo("office") reuse, and the red-then-green test.
