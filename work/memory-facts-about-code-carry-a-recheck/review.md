# Review — facts about code carry a recheck (#88), round 2 (amended)

**Verdict: request_changes.** I approved earlier and withdraw that. The grader's risk grade raised two silent-wrongness defects that I missed and that I confirmed from the diff. I did not run the suite, but verify's `mise run check` was green.

## Must fix
1. **A missing `origin/main` records `check_failed` for every code fact in that project.** `Probe.git/2` treats any non-zero git exit as "ref gone". A repo with a different default branch, no remote, a moved path or no fetch yet fails every probe quietly. Strength drops and nothing is logged.
   - Fix: in `Recheck.repo_paths/1`, keep only repos where `git -C path rev-parse --verify -q origin/main` exits 0. If none are left, return `{:ok, :skipped}` and record no event.
   - Test: a project whose repo has no `refs/remotes/origin/main` gives `{:ok, :skipped}` and no event.
2. **Function refs to code the project doesn't own fail.** `CodeRefs` keeps only `fun` from any `Mod.fun/N`. A fact citing `Repo.all/1` or `Enum.map/2` therefore greps for a `def all` or `def map` the project never defines, and fails.
   - Fix: emit `{:function, _}` only when the module part starts with `Server.`.
   - Test: `CodeRefs.extract("use `Repo.all/1` and `Enum.map/2`") == []`.

## Should fix
3. **The sweep query isn't wrapped.** `sweep_fact_rechecks` only rescues per fact. If its query raises, `embed_missing` after it is skipped. Wrap the whole step in a rescue that logs.
4. **Revert leaves the events behind.** Name the cleanup in the `Recheck` moduledoc: delete `check_passed` and `check_failed` events whose detail is like `%server recheck: %`.

## Optional
- Filter to facts checked more than 24h ago in SQL (`is_nil(c.at) or c.at < ^since`). That avoids loading every live fact each sweep. It must still keep the verdict-counting batch, so that prose facts don't starve code facts.

## Round 1 findings, resolved
- Batch starvation, probe prefix false-passes and the silent rescue are fixed and tested. Probes are argv-only and never run the fact's own `check_cmd`.
