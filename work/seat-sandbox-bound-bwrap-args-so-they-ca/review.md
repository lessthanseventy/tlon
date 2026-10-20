# APPROVE — bound a seat sandbox's bwrap args (#455)

Reviewer: tzinacan (Claude). No free reviewer was at the builder's grade (greybeard), so the workline's own lead — me — ran review. Builder: hronir.

## Verdict: approve.

## What it does
- `@dev_caches` drops `mix`, `menard-scratch`, `tlon-scratch` (the unbounded growers — each gathers repos across every seat with no limit). Each seat gets its own `~/.cache/tlon-scratch/<seat>` write root via `scratch_root/1` + `seat_sandbox/2`, so its bwrap mounts count its own repos, not the box's history.
- `scripts/scratch.sh`: a seat (`TLON_AUTHOR` set) works under `<dir>/<seat>`; the operator's prune walks one level into seat dirs.
- Docs (AGENTS.md, docs/manual/tasks.md, tasks/server.toml) updated in the same change. Task 4 closed: `~/.cache/mix` holds only `Mix.install` caches, nothing in tlon/menard calls `Mix.install` (fact #2402), so read-only costs nothing — no launch-env change.

## Spec compliance
The plan's budget (7500 args, 45/repo, 65 fixed checkouts) is stated in the test comment and proven by a RED→GREEN budget test: pre-fix the seat's write roots included `mix`/`menard-scratch`/`tlon-scratch` seeded with 300 repos each → well over 7500; post-fix only the seat's own 40 + the bounded tool caches (2 each) count, (80+65)*45 = 6525. A second test asserts the growers and other seats' dirs are gone from `allowWrite` while `~/.cache/tlon-scratch/<seat>` is present. `menard run check --in server` green (1917 tests, 0 failed); `scratch.test.sh` 7/7 (a seat's worktree goes under its own dir; the operator's stays flat; the operator's prune reaches both). `TLON_AUTHOR` is the real stable seat env var (server/lib/server/orphans.ex, staffing.ex, mcp/spawn.ex; adapters/claude-code/launch.sh), not an invented one — task 3's "find the real var, don't invent one" ask is met.

## Findings
None blocking.

## Notes
- The 45 args/repo figure is derived from the aggregate (11059/260), not measured per repo — acknowledged in the plan's DoD. The test bakes in the budget; if a fresh seat still reports >7500 args after the restart, `@args_per_repo` is the recalibration knob. This is the plan's stated open item, not a defect.
- Real-number proof remains owed post-merge (operator/uqbar): `release:cut`, then `server:stop` + restart so a fresh launch picks up the profile change (a sandbox profile change takes effect only on a fresh launch — fact #2405); #298 (zunz) unblocks only after that. Proof is `git branch --show-current` running in a fresh seat's Bash (currently refuses "N bwrap arguments … at most 9000").