# verify: a rebase conflict is recorded as the branch's red, not retried (#429)

**Closes #429.**

A branch that does not rebase cleanly onto origin/main made `scripts/workline-verify.sh` post a note and
exit 1 without recording anything. `Server.Jobs.Verify.finish/5` reads "nothing recorded" as a run that
could not start, so Oban retried it three times and the last attempt raised a job_failed Need. That is
what happened on #291 (2026-10-20).

**What changed**

- At the rebase-conflict exit, the script records the conflict as evidence:
  `record-verify <tid> <slug> 1 rebase "<conflicting files>"`. `finish/5` then sends the workline back to
  build with `rebase (exit 1) — <conflicts>` through `red_verify`. No retry, no Need.
- The branch's `note` is dropped in verify mode, since the finding now reaches the thread once through
  `red_verify`. The fallback note stays only for when recording itself fails. Landing mode (`WORKLINE_GATE`)
  keeps its stdout message.
- The other three can't-run exits (no checkout, fetch failed, deps.get failed) are unchanged.

**How it was checked**

- Test first: a new case in `server/test/server/workline_verify_script_test.exs` gives the branch a
  conflict with main. It failed on the old script with the note recorded and no `record-verify` line.
- After the change: `menard run test --in server test/server/workline_verify_script_test.exs` is green,
  29 tests, 0 failures.
- `bash -n scripts/workline-verify.sh` passes.
