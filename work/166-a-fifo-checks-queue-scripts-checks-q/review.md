Approve.

Reviewed by the workline lead (tzinacan): no free reviewer at the builder's grade (greybeard) was available, so the lead took this review.

#166 A — FIFO checks queue. hronir built it in four commits plus pr.md.

No blocking findings.

What I verified:
- Mechanism is sound. A run takes a monotonic ticket under a flock on tlon-checks.seq and writes its wait entry in the same critical section (no take-but-invisible window — the "improvement over spec"); then only the lowest live ticket tries `flock -n 9`. A newcomer arriving as the slot frees is never lowest while B's entry is still on disk, so it can't touch the lock; once B has the lock its entry is gone, but B then holds fd 9, so the newcomer's `flock -n` fails. Either way the newcomer runs after B. The kernel's flock still does mutual exclusion.
- Dead-entry reaping is correct. The glob walks padded tickets in arrival order, reaping dead pids at the front until the first live one; a SIGKILLed waiter is removed by whoever next globs past it, so it can't block the line.
- The `alive` cmdline guard `checks-queue\.sh` is valid for every caller: the only direct invoker is tasks/server.toml:208 (run by shebang) plus the test; both carry the script name in argv. This is load-bearing — a false negative there would deadlock a waiter (its entry reaped by others while its `entry` var points at a gone file, so `head = entry` never holds and it never tries the lock).
- Fallback: if the wait dir or seq file can't be written, it falls back to plain `flock 9` and says so on stderr; no entry trap is set, no orphan.
- Traps, `9>&-`, exits 2/143/130, `CHECKS_UNQUEUED` and the holder file are unchanged, as spec'd. The entry-removal EXIT trap is replaced by the holder-clearing EXIT trap only after the entry is explicitly rm'd, so no double-trap leak.
- Room.checks/0 sorts and parses `<10-digit ticket>-<pid>`, ignoring non-matching names; its ExUnit test went red then green (verify's full gate on the branch: 1982 tests, 0 failures).
- I ran scripts/checks-queue.test.sh twice from my seat: 10/10 both times, no flake in the 20-round race. (The `Killed`/`Terminated` lines are the test killing waiters on purpose.)
- Docs in sync: AGENTS.md, docs/manual/tasks.md and the tasks/server.toml description all updated in this change.

Follow-up noted below (pid-reuse edge), not blocking.