# A PM and a release pointer — what's on main is not what's shipped — design

**Date:** 2026-10-07
**Status:** approved by Andrew (calls in §9); nothing built. Six steps in §8.
**Asked:** Andrew: *"not every PR at work is releasable. is there someone … watching over the
process at large and saying like 'if we were to release today, it should be this commit on main'
… this is quite literally a software factory version of a real office so what metaphors are we
missing?"* — and then: *"i don't think this is a sheriff job right? this feels like more of a
PM/idk kinda role."*

---

## 0 · The call

Today "main" and "production" are the same thing, and nobody decides when they should be. Every
approved workline lands on main, `Rollout.after_merge` restarts the service as soon as nobody is
mid-turn, and the desktop's flake input follows main too. Green is not releasable. Floor step 3
(build mode) is on main while the life room it was built for isn't, and a restart tonight killed
two verifies mid-run (#140, #145).

Four pieces, in the order they unlock each other:

1. **A change window.** A restart waits for in-flight `:verify` and `:landing` jobs, and a job
   a restart kills anyway is retried instead of being thrown away. This is a bug fix and it ships
   first, on its own.
2. **A `release` ref; production follows it.** `refs/heads/release` only ever fast-forwards to
   a commit already on main. The service is built from it and the desktop's flake input locks to
   it. A deploy means moving the pointer. main can move as fast as it likes.
3. **A PM coworker owns the pointer.** A new archetype, `pm`, decides what's releasable. Four
   mechanical checks feed that decision (§4). The PM brings the release to Andrew as one gate,
   or moves the pointer itself under the standing approval when the release grades low-risk.
   The PM also owns what tertius doesn't: the backlog's priority and the changelog.
4. **Flags, not branches, for multi-step tracks.** A step can land on main dark and turn on
   when its track is done. The PM decides when a flag flips.

**What this is not:** git flow. Long-lived `develop`/`release` branches and merge commits fight
the rebase-only, merge-queue setup. `release` here is a pointer, never a branch anyone commits on.

## 1 · Roles: who does what

| Role | Archetype | Owns | Does not own |
|---|---|---|---|
| tertius | `surveyor` | routing: who does a ticket, staffing, gates up to the root thread | what matters most or what ships |
| **PM** (new) | `pm` | backlog priority, what's releasable, the `release` pointer, flags, the changelog | code, routing |
| sheriff | `sheriff` | incidents: red verifies, bounces, stuck worklines, failed schedules — plus postmortems (§7) | the release decision |
| reviewer | `reviewer` | the diff | whether the product works when used |

The sheriff is the right home for incidents, which is all it does today (`Sheriff.report/2` and
its five callers). The release decision is a product call: is this track whole, should this stay
dark, what do we tell Andrew changed. That belongs to a PM, so the sheriff stays as it is.

## 2 · The change window (ships first)

**Problem.** `server:restart` stops the server, which kills `workline-verify.sh` (exit 143), and
the job is discarded. Oban has no Lifeline plugin, so a killed job stays `executing`, and Verify's
`unique` constraint then blocks re-enqueueing it. PR #72 makes Verify retry (`finish/5`,
max_attempts 3), but `Jobs.Land` is still max_attempts 1. A restart mid-landing-gate looks red and
bounces the workline to build.

**Fix.**
- `Server.Rollout.quiet?/0`: nobody mid-turn (`Presence.Thinking`, as today) **and** no
  `oban_jobs` row in queues `verify` or `landing` with state `executing`. `restart_when_quiet`
  waits on it instead of on thinking alone.
- `server:restart` (tasks/server.toml) asks the running server whether it is quiet, and refuses if
  it isn't. `-- --force` overrides, because Andrew will sometimes need to restart anyway. If the
  server is down, the question can't be asked, so the restart proceeds.
- `Jobs.Land` gets the same treatment as Verify: an interrupted gate is retried, and only a gate
  that actually ran and failed bounces the workline.
- Add Oban's `Lifeline` plugin so orphaned `executing` rows get rescued after a restart.

**Check.** A test kills a running Verify and a running Land job: both are retried, and neither
bounces. A driven `server:restart` while a verify is running refuses, and `--force` restarts.

## 3 · The `release` ref

**Shape.** `refs/heads/release` in the live checkout, pushed to origin. It only fast-forwards,
and only to a commit that is an ancestor of `main`. A new `Server.Release.Pointer` does the move,
refuses a move that isn't a fast-forward from the current release to a commit on main, and
records event `release:<sha>` holding the checks' results and the changelog.

**What follows it.**
- **The service.** `serverRel` (ficciones `flake.nix:367`) points at the live checkout's
  `_build/prod/rel/server`, which is built from main HEAD. It moves to a dedicated release
  worktree, `~/projects/tlon/.release`, checked out detached at `release`. `server:release`
  builds there. The live checkout keeps tracking main, because the service judges workline
  artifacts against its HEAD and must never switch branches.
- **The desktop.** ficciones' `tlon` flake input changes from `…/tlon` (main) to
  `…/tlon?ref=release`. `flake:bump` locks whatever `release` is.
- **Auto-redeploy.** `Rollout.after_merge` stops restarting on a merge to main. A restart
  follows a move of the pointer instead, through the same quiet-wait as §2.

**Deploy = move the pointer.** `mise run release:cut -- <sha>` (default: the PM's candidate) does
four things: moves the ref, rebuilds in `.release`, runs the quiet restart, and posts the
changelog. `mise run release:status` shows `release` vs `main`: how far behind, what's
waiting, what's flagged dark. Rolling back is `release:cut` to an older release, which is the
one non-fast-forward move. That also needs `--rollback` and is always Andrew's call.

## 4 · What makes a commit releasable

The PM proposes a candidate commit on main. It is releasable when all four hold:

1. **The gate passed on exactly that commit.** `check:main` (scripts/check-main.sh) already runs
   on a throwaway worktree at `origin/main`. Its `ScheduleRun` gains the sha it ran on, so "the
   nightly passed on X" is a lookup, not an inference.
2. **A smoke test of the running product passed.** Build the candidate in a scratch release,
   start it on a scratch port and db, then hit `/api/office` and drive the office headless
   (the `drive-office` skill's path) through a fixed short script: open, a thread, a card, `R`.
   `server:doctor` runs against the dev scratch db and can't answer whether prod works, so the
   smoke check doesn't use it.
3. **No track is half-shipped where you'd see it.** Every multi-step track's user-visible
   surface is either complete at the candidate or behind an off flag. The PM checks this
   against the tracks in `docs/plans/` (§8 tables) and the flags (§5).
4. **Nothing is mid-flight.** §2's `quiet?/0`.

Checks 1, 2 and 4 are mechanical. Each passes or fails, and the PM reads the result rather than
re-doing it. Check 3 is the PM's judgment, and the reason the role exists.

**Who approves.** The PM grades the release with the same `Server.Workline.Grade` axes,
summed over what changed since the current `release`. If the grade fits the standing
`auto_land_risk`, the PM cuts it. Otherwise it reaches Andrew as one `Needs` gate, "release
<sha>: N changes, changelog, checks", with approve or not-yet. Anything the grader already
holds for the operator (a migration, a dependency, gate files) always waits.

## 5 · Flags

[`fun_with_flags`](https://github.com/tompave/fun_with_flags), on the stack the server already has:
its Ecto persistence adapter on the live Postgres, and Phoenix.PubSub to bust each node's cache
when a flag changes. That means no Redis and no restart to flip one. Its actor gates mean a flag
can be on for one workspace (`home`) before the rest. The office kit gets the flags in the office
snapshot (a `flags` map) and never reads them itself. Adding it is a dependency and a migration,
so step 5's PR always waits for Andrew (`Grade` hard limits).

A step that lands dark ships with its flag off, and its PR names the flag. The PM turns the flag
on when the track's last step reaches `release`. One release after a flag is on, it gets deleted
along with its branches in code, so flags don't pile up. That cleanup is a ticket the PM opens.

The first user is floor step 3: build mode goes behind `:build_mode`, off until the life room
(step 5) ships.

## 6 · The PM's other jobs

- **Backlog priority.** `Server.Intake` picks the most urgent unblocked ticket by `@urgency`. The
  PM is the one who sets urgency and reorders, and posts a short "what's next and why" to the
  root thread when it changes. tertius keeps routing whatever intake picks.
- **The changelog.** At each cut, a "what shipped to you" list built from the worklines and
  commits between the old and new `release`, in Andrew's words, not commit subjects. It is posted
  to the root thread and kept in the `release:<sha>` event.
- **QA, at first.** The smoke script in §4.2 is the PM using the product. Tonight's three
  user-only bugs (`R` relaunch, office tests in UTC, evals into the live db) would each have
  added a line to it. A separate QA coworker that explores beyond the script waits until the
  scripted pass proves too thin (§10).

## 7 · Sheriff: postmortems

When a `Sheriff.report` incident is resolved, the sheriff writes a short "what broke, why, what
changed (PR)" note and banks it as a fact. That way repeats show up as a pattern rather than as
lore. That is its whole addition here.

## 8 · Steps, each gated

Every step is a PR on main with green `mise run check` and its own check below. Step 1 is
independent and urgent. Steps 2→3→4 stack. Step 5 can open any time after step 2.

| # | Step | Check |
|---|---|---|
| 1 | **Change window** — `quiet?/0` counts jobs, `server:restart` refuses unless quiet, Land retries an interrupted gate, Lifeline plugin | a killed Verify and a killed Land are each retried, not bounced; a restart during a verify is refused, `--force` restarts |
| 2 | **The `release` ref** — `Release.Pointer`, `.release` worktree, `release:cut` / `release:status`, `after_merge` stops restarting; the ficciones side (`serverRel`, `?ref=release`) as its paired PR there | a cut to a commit not on main is refused; after a cut, the running service's version is the release sha while main is ahead |
| 3 | **Releasable checks** — `check:main` records its sha; the scratch-release smoke script | a candidate whose nightly ran on a different sha is not releasable; a broken `/api/office` fails the smoke |
| 4 | **The `pm` archetype** — role prompt, MCP tools (`release_status`, `propose_release`, `cut_release`, `set_urgency`, `flip_flag`), the release gate in `Needs`, the changelog | a driven session: the PM proposes, the gate reaches Andrew, approve cuts it, the changelog posts |
| 5 | **Flags** — `fun_with_flags` (Ecto + Phoenix.PubSub), snapshot `flags` map, build mode behind `:build_mode` | with the flag off, the driven office has no `B`; on, it does |
| 6 | **Sheriff postmortems** | a resolved incident yields one fact with the PR linked |

## 9 · Decided (2026-10-07)

- **The PM is its own role**, separate from tertius (routing) and the sheriff (incidents).
- **Cadence: the PM proposes, Andrew agrees.** No fixed schedule. When something releasable is
  waiting, the PM proposes a cut with its changelog. A cut that fits `auto_land_risk` it makes
  itself, and says so.
- **Standing approval reuses `auto_land_risk`** as it is.
- **Flags are `fun_with_flags`**, not a file (§5).
- **Who's who on the bench** is its own design: `2026-10-07-roster-design.md`.

## 10 · Still open, settled by trying

- Whether the smoke script needs a full scratch release or can run against `mix` in dev. Try the
  release first, since that is what ships.
- A standalone QA coworker, once the scripted smoke misses something a person caught.
- Change-window coverage beyond verify and landing (schedules, intake). Add a queue when a
  restart is caught hurting it, not before.
