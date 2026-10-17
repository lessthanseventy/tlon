approve

# release-smoke-refuses-already-being-smok — review

## scope
The branch's own change is 2 commits (5d63bca + 99a3996) on `scripts/release-smoke.sh`, `server/test/server/release_smoke_script_test.exs`, and `pr.md`. The wide diff stat against `origin/main` is staleness, not scope creep: the branch is 9 commits behind main (main advanced on `office/kit/entry.ts`, `needs`, `toy_pool`, `grade`, `workline` — none touch `release-smoke.sh`), so landing's rebase onto `origin/main` brings those in cleanly. Those files are not part of this change.

## what it does
On a lost flock the holder is now real only if its pid lives (`kill -0`), its url answers (`curl /api/office`), or its record is under 20 min old; otherwise the lock file is replaced and re-taken, saying so. The record is truncated on write, and the scratch node is started with `8>&-` so its daemons (epmd) cannot inherit the commit lock. This matches the ticket and `pr.md`, and the two shipped learnings (2127–2129).

## correctness
- The refuse condition is conservative in the safe direction: any positive signal (live pid, answering url, young record) refuses; only all-three-negative reclaims. The dangerous failure — reclaiming a lock a live run holds and stacking a second 2 GB build — is well-guarded.
- Cross-namespace pid: `kill -0` true on a collided pid in another namespace causes a false *refusal* (safe), never a false reclaim. The 20 min age backstop bounds how long a real second smoke waits on an orphan.
- fd-8 offset: in every path that reaches the write, fd 8 is at offset 0 — either a fresh open (flock succeeded, no read) or a reopen after reclaim. `: >"$lock"` truncates and the record writes clean; no NUL-gap from the earlier `head -n 1` read.
- Reclaim race: between `rm` and `exec 8<>` a competing run can take the lock; the second `flock -n` fails with its own message. No corruption window.
- `curl` without `-f` treats any HTTP response as "live" — correct for a booting node that may 500; only connection failure reads as gone.

## tests
Red→green is evidenced (learning 2131: 9/10 → 10/10). The three lock tests cover: live holder refused (existing), gone holder reclaimed (new), old record with an answering url refused (new). All three align with the condition's three clauses.

## non-blocking observations
- The "gone holder reclaimed" test's positive assert (`~r/on :4599/`) prints at line 56, *before* the lock, so it holds whether or not the reclaim happens; the `refute "already being smoked"` is what actually proves the reclaim. Strengthening it to assert the "reclaiming the lock" line would prove the positive path. → follow_up.
- 5d63bca + 99a3996 are a fix and a format-only fixup; the first could have been formatted before commit. Harmless on a rebase-merge; noting only.
- The epmd/fd-8 cause is an untested hypothesis (emma disclosed, learning 2132); the `8>&-` change is sound defensively regardless, and the reclaim does not depend on it.