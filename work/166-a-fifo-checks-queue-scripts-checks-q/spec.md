# #166 A — FIFO checks queue

## Problem
`scripts/checks-queue.sh` is a plain `flock`: when the slot frees, whoever grabs the lock first wins, so a newcomer's `flock -n` can beat a check that has waited longer.

## Design
Mutual exclusion stays the kernel's `flock` on fd 9 (unchanged, so two suites can never run at once). Ordering is a gate in front of it: **nobody tries the lock unless they hold the lowest live ticket.**

1. **Ticket.** Every run, contended or not, first takes a sequence number: under `flock` on `$dir/tlon-checks.seq` (fd 8), read the integer in that file (0 if empty), add 1, write it back, release. Monotonic per boot; mtime is never used.
2. **Entry.** `$dir/tlon-checks.wait/<seq>-<pid>`, seq zero-padded to 10 digits (so `ls` order is ticket order). Content is the one line the waiter file holds today: `<label> (pid N) in <dir> since HH:MM:SS`.
3. **Turn.** Loop: drop every entry whose pid is dead; if my entry is the lowest left and `flock -n 9` succeeds, delete my entry and run; else sleep `${CHECKS_POLL:-0.5}`s. A newcomer therefore always queues behind existing entries, including one arriving the instant the slot frees: it is not lowest, so it never touches the lock; the head takes it on its next poll.
4. **Dead waiter.** Live = `/proc/<pid>` exists and its cmdline contains `checks-queue.sh` (guards pid reuse). A dead one's entry is removed by whoever notices, so a killed check cannot block the line.
5. **Unchanged:** the holder file and its line, the `exec 9>>` refusal (exit 2) and `CHECKS_UNQUEUED`, the waiting message, `trap ... EXIT` clearing the holder, `setsid "$@" 9>&- &`, and the TERM/INT traps killing the child's process group (143/130). The wait-entry EXIT trap stays too (rm my entry).
6. **Degrade.** If the wait dir or seq file cannot be written, fall back to today's plain `flock 9` and say so on stderr. Never deadlock on bookkeeping.

## Wait-entry format (for B's rack reader)
File name `^\d{10}-\d+$`: ticket, then pid. Holder file is unchanged. `Server.Office.Room.checks/0` (room.ex:208-212) currently treats the whole name as a pid; change it in this commit to parse the pid after `-`, ignore non-matching names, check `/proc/<pid>`, and return `waiting` sorted by ticket.

## Tests (written first)
`server/test/checks_queue_script_test.exs` (new, runs the real script in a tmp `XDG_RUNTIME_DIR`, `CHECKS_POLL=0.05`, commands that append their name to a log):
- A holds; B then C queue; release A; the log reads A, B, C.
- C arrives exactly as the slot frees (C started right after A's holder exits, B still polling): log is B, C. Run this in a loop of 20 to shake the race.
- A waiter SIGKILLed while waiting: its entry is reaped and the next waiter runs.
- Two suites never overlap (log has start/end pairs, never interleaved).
- Room.checks/0 test: entries `0000000002-<live pid>` and `0000000001-<live pid>` read back in that order with a running holder; a dead pid is dropped.

## Done
`menard run test --in server test/checks_queue_script_test.exs` and the Room.checks test pass; `menard run check --in server` green; AGENTS.md checks-queue paragraph still true (add one line: waiters are ticketed FIFO).

## Open (assumed, shout if wrong)
- 0.5 s polling is acceptable latency for a multi-minute suite.
- The cmdline guard `checks-queue.sh` holds for every caller (run-from-root.sh, mise); I will verify before building.
