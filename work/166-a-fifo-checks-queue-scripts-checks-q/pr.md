The checks queue is first come, first served. Closes part 1 of #166 (part B, the rack's one list and the pending restart, stacks on this).

`scripts/checks-queue.sh` was a plain `flock`: when the slot freed, a newcomer's `flock -n` could beat a check that had waited longer. Now every run takes a monotonic ticket (`tlon-checks.seq`, under its own flock) and writes `tlon-checks.wait/<10-digit ticket>-<pid>` in the same critical section, and only the lowest live ticket may try the lock. The kernel's flock still does the mutual exclusion. A waiter whose pid is gone, or is no longer `checks-queue.sh`, is removed by whoever notices it. Bookkeeping that can't be written falls back to the plain lock and says so. The holder file, the traps, `9>&-`, exits 2/143/130 and `CHECKS_UNQUEUED` are unchanged. `Server.Office.Room.checks/0` reads the new entry names, in ticket order.

How it was checked:
- `scripts/checks-queue.test.sh` (new, run by `check:names`) drives the real script:
  - A, B and C run in arrival order, including C arriving as the slot frees (20 rounds). With the head-only guard removed, that case goes red as `A C B`.
  - A SIGKILLed waiter doesn't block the line and its entry is reaped. A TERMed waiter removes its own entry.
  - Two checks never overlap.
  - Fallback works.
- Against the old script, the two kill cases and the fallback were red.
- `room_test.exs` was red, then green.
- `menard run check --in server`: 1982 tests, 0 failures.
- `mise run check:names` and `manual:check` are green.
- I did a manual contended run: the second check waits, then runs, and the wait dir ends up empty.
