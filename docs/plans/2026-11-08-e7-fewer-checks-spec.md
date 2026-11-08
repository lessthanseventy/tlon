# E7 · Fewer check runs, the same safety: a spec

Outside-pass item E7 (`2026-11-07-outside-pass-plan.md`). It changes the check, so it is
Andrew's limit gate: this spec first, then one PR per mechanism, none merged without his go.

## What a landing costs today

Passed check events in the 7 days to 2026-11-08 (`event`, `kind = 'check_passed'`, grouped by
correlation):

| run | passes |
|---|---|
| verify (`workline:…:verify`) | 70 |
| no correlation (a seat's `run_task`) | 47 |
| landing gate (`workline:…:landing`) | 24 |

Over that week 24 worklines landed, so each landing cost about five full suites before the
nightly `check:main` ran a sixth on a tip that was usually the landed tree. Failed runs and
send-backs come on top.

## The rule that does not change

Nothing merges that nobody checked. Every PR merged to main carries a `tlon/check` posted by a
full `mise run check` at exactly its head (the landing gate). Everything below removes runs
*before* that gate, or the nightly *after* it; neither touches the gate itself.

## Mechanism 1 · One green per tree (half done)

Done 2026-11-07: `scripts/check.sh` skips a clean tree whose gate-relevant hash already passed,
the hash leaving out `work/` and `docs/` except the two docs a check reads. The record is
`~/.cache/tlon-verify/green/<tree>`, one directory per machine, so every checkout already shares it.

Left:
- `run_task("server:check")` from a seat runs only the server half and records nothing in the
  green cache, so the verify after it runs the full suite anyway. Change: a seat's `run_task`
  of `check` (already in `@tasks`) records green as `check.sh` does; the seat prompt says to ask
  for `check`, not `server:check`, before advancing. Cost: a seat's pre-advance run grows from the
  server suite to the full one, once; verify then hits the cache when the branch did not move.
- Keep the record a file. Moving it to the db (the plan's wording) buys nothing on one machine
  and makes `check.sh` depend on the service being up.

## Mechanism 2 · Verify scoped by what changed; the landing stays full

`workline-verify.sh` runs `mise run check` today. Change: verify picks the suites from the diff
against its merge base, by one pure function `Server.CheckScope.suites/1` (paths in, task names
out), which the script asks for over the API:

| the diff touches | verify runs |
|---|---|
| only `server/` | `server:check` |
| only `office/` | `office:check` |
| only `adapters/` | the adapter's check |
| only `scripts/` or `tasks/` | `check:scripts` (G6) and `check:names` |
| only `docs/` or `work/` | `check:names` |
| two or more of these, or `mise.toml`, `scripts/check*.sh`, any `AGENTS.md`, `.github/` | the full `check` |

The landing gate keeps running the full `check`, and only it posts `tlon/check`. A scoped verify
posts nothing to GitHub.

Risk: a change in one module that breaks another (a server API change breaking the office's
reads) passes verify and fails at landing, one round later than today. That is a slower red, not
a missed one, because the landing is still full.

## Mechanism 3 · The landing's gate is the nightly

Half shipped as E2 (PR #801): an immediate merge records `gate` on main's new tip when the tree
matches. Left:
- The 03:00 `check:main` schedule skips a tip `Candidate` already reads green for, and says so in
  its run (`skipped: gate passed at landing, run #N`), so the record stays readable.
- The smoke is queued after a merge (`Server.Jobs.Smoke` in its unheld mode) instead of waiting
  for the night; one at a time, a newer merge replacing a queued one.

## Mechanism 4 · The bench and the script suites run when their inputs change

- The canary bench runs when `mix server.bench_contrast --fingerprint` differs from the last
  run's, not nightly.
- The nine script suites in `check:names` move to `check:scripts` (G6) and run when `scripts/`
  or `tasks/` changed. The full `check` still runs them all.

## Order

1. Mechanism 3's schedule skip and post-merge smoke (smallest; relies on #801).
2. Mechanism 1's `run_task` green record.
3. G6's `check:scripts`, then mechanism 2, its scoping function tested first.
4. Mechanism 4's bench trigger.

## Questions for Andrew — answered 2026-11-08

1. Mechanism 2 moves a cross-module break from verify to landing. Acceptable? **Answer: yes;
   the landing stays full.**
2. Mechanism 1 makes a seat's pre-advance check the full suite. The alternative is to drop the
   seat's own run and let verify be the first; that saves more and gives the builder its red
   later. Which? **Answer: the seat's pre-advance check is the full `check`, recorded green.**

The spec is approved; each mechanism is its own PR, merged by Andrew (the check is his limit).

## Check

- Passed check events per landed workline, for the week after against the week above; the aim is
  two (verify and landing) where the tree did not move between them, one where it did not move
  since the seat's own run.
- Every PR merged in that week has a `tlon/check` from a full run at its head (`gh api` over the
  week's merges).
- `CheckScope.suites/1` tested over fixture diffs, including that a `server/`-only diff never
  skips the server suite and that each listed cross-cutting path forces the full set.
