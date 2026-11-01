No free reviewer is at the builder's grade (greybeard); reviewed by runeberg (glm), one grade down. Read the diff only. I did not run the tests or the gate.

# Verdict: approve

Right then. The change does what #664 asks. `health_since` is now a table, one row per held problem, and a row is deleted when its problem clears. The read upserts with `on_conflict: :nothing` and returns the stored time, so concurrent readers can't overwrite each other's clock. The migration, the doctor table list and the three test edits all match the code. I found no blocking defect.

Findings, none blocking:

1. **Nil `at` if two readers race.** Reader A inserts `tmux`. Reader B, whose reading has no `tmux`, deletes it. A's `Repo.all` then returns no `tmux` row, so `stored[...]` is nil and the Need gets `at: nil`. Downstream compares such as `DateTime.compare(at, …)` would then raise. It needs two readings that differ at the same moment, so it is rare, but a `|| now` fallback in the final `Map.new` closes it.
2. **Cost per read.** The old code did a `persistent_term` read and wrote only when the set changed. This one runs a DELETE, an INSERT … ON CONFLICT and a SELECT on every `Needs.list` / `grouped`, whether or not anything changed. If the office or API polls these often, that is three round-trips per poll. The cheap shape is one SELECT, then write only when the set differs from the stored rows. I have not measured the poll rate.

Test coverage is good. It covers survival across reads, clearing on resolve, and a fresh clock when the problem returns. It does not cover finding 1.