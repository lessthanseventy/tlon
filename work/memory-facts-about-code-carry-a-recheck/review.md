VERDICT: APPROVE

Scope: `git diff main...HEAD` for server/lib and tests (CodeRefs, Probe, Recheck, Sweep), at head 579cffb, against plan.md. I read the code. I did not re-run the gate; verify recorded `mise run check` green.

Findings, none blocking:
- Probes are argv-only (`System.cmd` with `git -C`), run against `origin/main`, and escape the name. The server never runs a fact's own `check_cmd`. Repos without `origin/main` are skipped, so there are no false `check_failed` events.
- Facts that assert an absence yield no refs, so a passing probe cannot boost a claim the code now contradicts. Refs to modules the project does not own yield none.
- Recheck is idempotent inside 24h and records `check_passed`/`check_failed` correlated `fact:<id>`, so `Strength` picks it up. The undo path is documented.
- The sweep orders the least recently checked first and counts only facts that got a verdict toward the batch of 25. Both the sweep and each per-fact recheck rescue and log, so one bad fact cannot stall the sweep.
- Cost note: facts that always skip (prose, or no project repo) have no check event, so they sort first and are re-walked every sweep. The cost is a regex plus one thread lookup per fact, and `Repo.all` loads every live fact each time. That is fine at current scale. If the fact count grows, move the ref filter into the query or add a LIMIT-based scan.
- `Server.Mod.fun/1` is a weak signal: any `def fun` on main satisfies it. The moduledoc says so.
