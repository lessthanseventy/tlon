# E1 · Every ending says so: a spec

Outside-pass item E1 (`2026-11-07-outside-pass-plan.md`). Spec first, for Andrew's go before code.

## What is true today

- `Server.Jobs.Alarm` rides `[:oban, :job, :exception]`: a job that raises, or returns
  `{:error, _}` on its last attempt, posts `⚠ job … discarded` on the standing machine thread,
  once per repeat. `Server.Office.Needs`' `job_failed` lists discarded jobs for a day.
- Nothing listens to `[:oban, :job, :stop]`. Its metadata carries `:state` (`:success`,
  `:cancelled`, `:discard`, `:snoozed`) and `:result`, the `perform/1` return value (Oban 2.24).
- A job that ends badly but returns `:ok` or `{:ok, _}` is a success to Oban and to the alarm.
  So is a job whose outcome post goes to a nil thread.

## The seven tickets are four different defects

| ticket | what ends silently | kind |
|---|---|---|
| #846 | `PRLanding` refuses a landing; `post(nil, _)` drops it; the `Land` job reads completed | a job's bad ending returned as a value, to no thread |
| #793 | `BranchReview.record/1` writes a check event and ends the review session; no message | a success that posts nothing |
| #841 | `release.sh` exits 0 on a 409; `PM.cut` ignores the restart's answer | a caller ignoring a returned error |
| #812 | the redeploy unit's second quiet check refuses after the waiter has exited | a systemd unit nobody waits on |
| #750 | `smoke-build.sh` waits on `flock 5` with no bound; the schedule kills it at 30 min | a shell wait with no bound |
| #781 | a crew reviewer's window disappears with no verdict | a seat that vanishes |
| #864 | a workline's lead in another repo is never launched | a spawn that fails without a trace |

Only #846 and #793 are a job (or a job's callee) ending without a post. One invariant over
`Server.Jobs.*` fixes those two and prevents the next. The other five each need their own fix,
listed under "The instances" below; the invariant does not reach them, and pretending it does
would leave them open.

## The invariant

**A job about a thread ends with one line on that thread. A job about nothing in particular
ends silently on success and with one line on the standing thread otherwise.**

1. *About a thread* means its args carry `"thread_id"` or `"on_thread"`. When that is nil (a
   verdict recorded by hand, #846), it falls back to the standing thread; never to nowhere.
2. The line comes from one handler, `Server.Jobs.Outcome`, attached beside `Alarm` to both
   `:stop` and `:exception`. A job states its outcome by its return value:
   - `{:ok, line}` with a binary `line`: posted as `✓ line`.
   - `{:error, line}` / `{:cancel, line}` / a raise: posted as `✗ line` (or the exception's first line).
   - `:ok` from a thread-bound job: posted as `✓ <worker> done`. A job that wants no line on
     success returns `{:ok, :quiet}`, and the test below requires a reason beside it.
   - `:snooze`: nothing (it is not an ending).
   `Alarm` keeps the standing-thread line for unbound jobs, and gains `{:cancel, _}`, which
   today ends a job with no event it listens to.
3. A job whose callee already posted its own outcome (the `Land` job's `PRLanding` posts `✓
   merged at …`) returns `{:ok, :posted}` so the line is not doubled. The handler's only job
   then is the nil-thread fallback.
4. Repeats on one thread collapse as `Alarm.post/1` already does (skip when it is the latest
   message), so a periodic sweep failing every minute stays one line.

## How it is enforced

`test/server/jobs/outcome_contract_test.exs` lists every module under `lib/server/jobs/` that
`use`s `Oban.Worker` (read from the code, so a new job cannot be missed) and requires each to be
in exactly one of two tables in the test:

- **bound**: a fixture job and a stubbed failure path; the test runs it through
  `Oban.Testing.perform_job/3` with the handler attached and asserts one `✗` line on the
  fixture's thread, and for a nil thread, on the standing thread.
- **unbound**: a one-line reason it is about no thread (`Dispatch`, `Drain`, `Maintain`,
  `KeepUp`, …). The test asserts its failure reaches the standing thread.

A worker in neither table fails the test with its name. That is the invariant: no job can be
added that ends without saying so.

## The instances

Each ships as its own small PR after the invariant, and closes its ticket.

- **#846**: falls out of rule 1. `Land`'s args carry `on_thread`; nil goes to the standing thread.
  `land.sh`'s help text is corrected to say so.
- **#793**: `BranchReview.record/1` posts the verdict line on the review's thread (and the
  branch's workline thread when there is one) before it ends the session. That is not a job, so
  it gets its own test in `branch_review_test.exs`.
- **#841**: `PM.cut` matches the restart's answer and posts the refusal; `release.sh` exits 1 on
  a 409, as #837 did for the scripts-only path.
- **#812**: `server-restart.sh` reports a refused second check back (`POST /api/restart/refused`,
  or the unit's exit read by `Rollout` after `systemd-run --wait`); the cut's thread hears it and
  `restart_pending?` stays true.
- **#750**: `flock -w` bounded under the schedule's 30 minutes, printing the queue word while it
  waits, as #603 did for the commit lock.
- **#781** and **#864** are B5's: a seat with a session row and no window, or a lead assigned
  with no session after N minutes, is an ending; Staffing posts it on the thread. They pair with
  B5's timeouts, not with Oban.

## What this does not do

- It does not post on success for unbound jobs: `Dispatch` runs every minute.
- It does not catch a job killed by a restart (Oban's Lifeline rescues it to `available` or
  `discarded` with no event). B6 covers the wording for that.
- It does not change any job's retry policy (B6).

## Questions for Andrew — answered 2026-11-08

1. A thread-bound `:ok` posting `✓ <worker> done` by default: right, or should silence be the
   default with `{:ok, line}` the opt-in? The default here is loud, so a forgotten case is noise,
   not silence. **Answer: loud by default; `{:ok, :quiet}` opts out.**
2. The fallback for a nil thread is the standing (root) thread. The plan also names the sheriff's
   beat; one target is simpler. Which? **Answer: the root thread, only.**

The spec is approved as written; the PRs follow.

## Check

- The contract test, red on today's tree (it names `Land` and every bound job missing a fixture),
  green after.
- #846 replayed: a landing recorded with no thread, gate failing, posts `✗` on the root thread.
- The five instance PRs each carry their ticket's own check.
