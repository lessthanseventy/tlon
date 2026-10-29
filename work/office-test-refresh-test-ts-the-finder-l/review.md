APPROVE. Note: no free reviewer at the builder's grade (greybeard); runeberg reviewed.

Reviewed origin/main...HEAD (4 commits, 24 files; office tests + office/AGENTS.md only).

- test/started.ts: a TUI start gets its own 120 s budget (STARTED), and the test timeout is TUI_TEST = 180 s. A pane whose process exited fails at once (capture-pane exit != 0), naming tmux's stderr; a start that never paints fails with the pane contents. The logic is correct.
- started.test.ts covers all three paths: paints in time, pane gone, never paints. I ran it with refresh.test.ts: 4 pass, 0 fail. I did not run the full office suite or the gate.
- Call sites: every first-paint wait is now started(...). In refresh.test.ts the per-test deadline moved inside until(), so each step has its own 25 s; that fixes the shared-deadline starvation. reload.test.ts uses started() for the post-R repaint, which is reasonable.
- The remaining 40_000 timeouts in cast-view.test.ts belong to later tests reusing the already-started TUI, not cold starts.
- office/AGENTS.md is updated in the same change.

No blocking findings.