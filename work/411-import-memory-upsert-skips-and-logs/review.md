APPROVE — workline 411 (import memory: skip and log a junk-filtered memory)

Read: server/lib/server/import/memory.ex and test diff against main.

- The fix is right. `refused?/1` calls the public `Fact.junk?/1`, the same predicate `bank_changeset` validates with. It runs before `upsert`, so a placeholder memory no longer hits `{:ok, _} =` and raises on the insert. It also no longer overwrites an existing fact through the `Repo.update!` path, which bypassed the changeset.
- Surgical: one filter in the pipeline plus one private function. The `Logger.warning` names the memory.
- Tests cover both paths: a placeholder is skipped and logged while the rest of the import continues, and a placeholder does not overwrite an existing fact.
- Not verified by me: I did not run the suite (no DB in my seat). verify and the landing gate run it.

Nit, not blocking: skipped memories are not counted in the returned tally. The warning log is the only signal, which matches the ticket's "skip and log".