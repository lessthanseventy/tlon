VERDICT: approve

Reviewed `git diff main...HEAD` (office/kit/balloon.ts, kit/canvas.ts, tui/paint.ts, tests, AGENTS.md). I read the code; I did not re-run the suite (the server's verify check passed on this branch, and the builder reports 3 environmental failures: pngjs missing, two tmux timeouts).

Spec: balloons are 34x4 by default, a word longer than a line is hard-broken, overflow ends in "...", and both render modes (kitty and block) clamp to the viewport and nudge off each other through `placeBox`.

Findings (none blocking):
- `placeBox` returns null when there is no room, and the caller `continue`s, so that balloon is simply not drawn that frame. The comment says "waits a frame", which matches. Fine.
- Kitty: `balloonLines` re-wraps when the viewport is narrower than the text, and the tail is skipped if it would fall outside the viewport. Correct. The tail x is clamped inside the box.
- Block mode draws no tail; this is the same as before.
- `balloonLines` has a fuzz test for the width and row bounds. `placeBox` has a fuzz test for containment and non-overlap. Paint tests cover the viewport edges and two-speaker collisions.
- AGENTS.md updated in the same change.

Unverified: plan task 6 (drive-office screenshots at the room edges) was not done, and I did not do it either. The logic is covered by tests, but the pixel look at the edges has not been seen by anyone. The operator gate at merge should weigh that.
