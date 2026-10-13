# The requeue_stranded discard cap is per approval

Closes #111 (follow-up from #224, raised by lonnrot).

`Server.Workline.requeue_stranded` counted every discarded Land job a thread ever had, so once a
landing had been discarded three times a fixed branch approved again sat at review until Oban
pruned the old jobs. Now the cap counts only the discarded jobs inserted at or after the standing
approval's record, so a fresh approval starts over while a cap hit under the current one still stops.

Two things made that count honest:
- `queue/3` recorded a new approval on every requeue and reopen, which would have reset the cap each
  sweep. A requeue or reopen under a standing approval now keeps it; only a fresh approval records one.
- The approval is recorded before its Land job (events are second-truncated), so the job's time is
  never before the record's.

`approval/1` also returns `"at"`, the record's time; its callers match on the map and are unchanged.

Checked: `test/server/workline_test.exs` has a new test (three discards cap it; a new commit approved
again requeues twice, then caps again) that went red first, and the existing bounded-requeue test
still holds. 63 tests, 0 failures in that file; `mise run check` run unsandboxed on the branch.
