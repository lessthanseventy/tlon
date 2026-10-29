# Review: hall-hire-test-the-second-launch-reuses @ ce51142

**Verdict: approve.**

One commit, two files: `office/test/navigation.test.ts` (+6/-4) and `pr.md`. Read in full against origin/main.

## What the diff does

1. `start()` names its socket `tlon-office-nav-${pid}-${++starts}`, so the play-card test's restart never touches the socket the first test's server is still dying on. This is exactly the fix the ticket's last sighting verified (5/40 → 0/40 on distinct sockets).
2. The mid-file kill (line 112) and the `afterAll` kill both go through `killServer`, which reads `#{socket_path}` from tmux before the kill and unlinks it. The hand-rolled `rmSync` on `TMUX_TMPDIR/tmux-<uid>/<socket>` is gone; `killServer` resolves the path from tmux itself, which is more correct (the helper's comment says why).
3. The `afterAll` kill only reaches the last socket; the first one is already killed at line 112 before the second `start()`, and a failing earlier test does not skip that line. No socket is left running.

## Spec compliance

The ticket asked for three things: fix navigation, apply the same to hall-hire, sweep the other kill-then-restart tests. I checked the builder's claim that the latter two need nothing:

- hall-hire.test.ts:30/58 and rack-card.test.ts:70 already use `killServer` on main.
- Every remaining bare `tmux("kill-server")` (answer-note, banter-off-quiet, cast-sandbox, answer-note-inbox, column-tree, confirm, entry-keys, margin-tip, persona-reroll, rack-card:36, reload, refresh, room-key, stalled-need, triage-actions, ticket-back) sits inside `afterAll` with no restart after it. Grep confirms it; none of them reuse a socket.

So the sweep found what it says it found. The builder was honest that no red-first test exists: the race is load-dependent, and the ticket's own loop repro is the evidence.

## Checks

`mise run check` on the branch: exit 0, office 958 pass / 0 fail. No `bench_contrast` row in CHECKS, so nothing to call a regression.

## Not blocking

The sixteen `afterAll` kills that bypass `killServer` leave a dead socket file under `tmux-<uid>/` per run. Harmless because each is a per-pid name, but it is the same shape of debt. Listed as a follow-up, not a reason to hold this.
