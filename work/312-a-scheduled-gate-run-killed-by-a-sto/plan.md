# Plan — a scheduled run killed by a stop is `interrupted`, not a red gate (#312)

Goal: a scheduled script that dies of SIGTERM/SIGKILL (exit 143/137) closes its `ScheduleRun` as
`interrupted`; no Sheriff 🚨; the gate-on-main reader treats the sha as "no check yet" so the next run is
the verdict. 124 (timeout) and any other non-zero stay `failed`.

Facts checked on origin/main (b17a8fb):
- `scripts/check-main.sh:30` and `scripts/release-smoke.sh` already have `trap 'exit 143' TERM` (added by
  cdc3f01, 2026-10-17 — *after* the 2026-10-13 incident). So the scripts probably already report 143 now; Task 6
  proves it rather than assuming. We do not match mise's text.
- Erlang reports a signalled child as exit_status 128+sig, so `kill -TERM $$` in `sh -c` lands as 143.
- A hand run killed by a signal never reaches `record_ran` (the EXIT path `exit 143`s first), so
  `Candidate.record/3` needs no change.

## Every reader of `ScheduleRun.status` (grep `status`/`"failed"`/`"ok"`/`ScheduleRun` in server/lib, office/)

| Reader | Today | With `interrupted` |
|---|---|---|
| `schedules.ex` `work/1` script (l.209–232) | `0→ok`, else `failed`, Sheriff.report on any non-zero | **change** (T1): 143/137 → `interrupted`, standing note says interrupted, no Sheriff |
| `schedules.ex` `perform/1` (l.170–181) | writes whatever `work` returns | none (pass-through) |
| `schedules.ex` agent/workline `work/1` | `ok`/`failed` | none (never interrupted) |
| `jobs/orphans.ex` `interrupt_runs/2` (l.78) | `where status=="running"` → `"failed"` | **change** (T2): writes `"interrupted"`; its `== "running"` guard is unaffected |
| `release/candidate.ex` `ran/3` (l.76) | `%{status:"ok"}` ✓, any other status ✗ with `"#{task} #{status}"` | via `newest/1` (T3) an interrupted run is never returned, so the sha reads "no gate on <sha>; its last run was on …" — the generic ✗ clause never sees it |
| `candidate.ex` `elsewhere/1` (l.89) | `newest` | same skip: "its last run was on" ignores interrupted runs |
| `candidate.ex` `record/3` (l.50) | `0→ok` else `failed` for hand runs | none (see facts) |
| `release/pm.ex` `running?/1` (l.128) | `status=="running"` | none: interrupted ≠ running, so a killed run no longer holds a restart/cut |
| `office/room.ex` `runs/1`, `last_runs/1` (l.479, 494) | passes `status` string through | none (pass-through) → reaches `/api/schedules/:id/runs`, `/office/schedules/:ws` |
| `staffing.ex` `duty_threads/1` (l.168) | selects `thread_id` only | none |
| `jobs/run_schedule.ex` | ignores the result's status | none |
| `office/tui/data.ts` l.357,359 types | `"running"\|"ok"\|"failed"` | **change** (T5): add `"interrupted"` |
| `office/tui/main.ts` `runGlyph` l.1148 | ok ✓, failed ✗, **anything else `…`** | **change** (T5): else an interrupted run would look *still running* |
| `release/pm.ex` state lines | built from `Candidate.lines` / `running?` only (no status match) | none |

No other file matches `ScheduleRun` (grep: schedule_run.ex, schedules.ex, staffing.ex, orphans.ex, candidate.ex, room.ex, pm.ex + migrations/tests).

Verify commands (run from `server/`): `menard run test <file>`. Final: `mise run check`.

---

## T1 — `Schedules.work/1` classifies 143/137 as interrupted, skips the Sheriff
Files: `server/test/server/schedules_test.exs`, `server/lib/server/schedules.ex`

1. RED — add after the `exit 3` test (≈l.172):
```elixir
  test "a script killed by a signal is interrupted, not failed, and the sheriff hears nothing", %{ws: ws} do
    s = schedule!(ws, %{cron: "@daily", body: "echo started; kill -TERM $$", standing: true})
    {:ok, run} = Schedules.run_now(s)
    assert %{status: "interrupted", exit: 143, thread_id: tid} = Schedules.perform(run.id)

    refute Repo.exists?(from t in Server.Thread, where: t.title == ^Server.Sheriff.beat_title())
    assert Repo.exists?(from m in Server.Message, where: m.thread_id == ^tid and like(m.body, "%interrupted%"))
  end

  test "exit 124 and other codes stay failed", %{ws: ws} do
    s = schedule!(ws, %{cron: "@daily", body: "exit 130"})
    {:ok, run} = Schedules.run_now(s)
    assert %{status: "failed", exit: 130} = Schedules.perform(run.id)
  end
```
(Check the file's existing aliases/imports for `Repo`, `from`; copy how l.171/:201 tests assert, and how other tests in the file detect a Sheriff report — reuse that assertion if one exists instead of the beat-title query.)
Run `menard run test test/server/schedules_test.exs` → first test red.

2. GREEN — in `schedules.ex` add `@interrupted_exits [143, 137]` near the other module attributes, and replace the script `work/1` status line and the Sheriff block:
```elixir
    interrupted = code in @interrupted_exits
    status = cond do code == 0 -> "ok"; interrupted -> "interrupted"; true -> "failed" end
    result = Map.merge(%{status: status, exit: code, output: tail}, ran_on(out))
```
standing note: `"⏰ #{s.title} — #{if interrupted, do: "interrupted (exit #{code})", else: "exit #{code}"}\n```…"`.
Sheriff block: `if code != 0 and not interrupted do`. Comment (why): "a stop or a kill is the operator's, not a red; the next run is the verdict".
(Format `cond` over lines as `mix format` wants.)
Done: both tests green, rest of file green. Commit: `schedules: a script killed by a signal is interrupted, not a red run (#312)`.

## T2 — Orphans close a discarded run as interrupted
Files: `server/test/server/jobs/orphans_test.exs` (l.84,99), `server/lib/server/jobs/orphans.ex` (l.80)
1. RED: rename the test to "…closes as interrupted…" and change the assertion to `%{status: "interrupted", output: "interrupted: " <> _, finished_at: %DateTime{}}`. Run → red.
2. GREEN: `status: "interrupted"` at orphans.ex:80. Update the comment above `interrupt_runs`.
Done: `menard run test test/server/jobs/orphans_test.exs` green. Commit.

## T3 — `Candidate.newest/1` skips interrupted runs
Files: `server/test/server/release/candidate_test.exs`, `server/lib/server/release/candidate.ex` (l.~99)
1. RED:
```elixir
  test "an interrupted run is no verdict: the sha reads as no gate yet, not red", %{s: s} do
    ran!(s, "gate", @a, "interrupted")
    ran!(s, "smoke", @a, "ok")
    assert %{gate: %{ok: false, why: why}} = by_check(Candidate.check(@a, quiet()))
    assert why =~ "no gate on aaaaaaa"
    refute why =~ "interrupted"
  end

  test "an interrupted run does not unseat an earlier pass on the same commit", %{s: s} do
    ran!(s, "gate", @a, "ok")
    ran!(s, "gate", @a, "interrupted")
    assert %{gate: %{ok: true}} = by_check(Candidate.check(@a, quiet()))
  end
```
2. GREEN: in `newest/1` add `where: r.status != "interrupted"` next to `not is_nil(r.finished_at)`; extend its comment ("an interrupted run is no verdict").
Done: candidate_test green (incl. existing "failed" tests). Commit.

## T4 — Docs say the third value
Files: `server/lib/server/schedule_run.ex` moduledoc ("then `ok`, `failed` or `interrupted` (a script killed by a signal, or a run the server's restart cut off: not a verdict)"), `Schedules.perform/1` @doc ("`ok`, `failed` or `interrupted`"). Doc-only; `mise run check` covers format. Commit with T2 or alone.

## T5 — Office board shows interrupted
Files: `office/tui/data.ts` (l.357, 359), `office/tui/main.ts` (l.1148)
- Types: `"running" | "ok" | "failed" | "interrupted"` (both).
- `runGlyph`: add `r.status === "interrupted" ? { s: "⊘", fg: ROLE.inactive }` before the `…` fallback (use an existing ROLE colour; `ROLE.inactive` is used at l.1153).
- No unit test: `runGlyph` is a private const in main.ts (a module with side effects, not imported by office/test/*). Verify with the office typecheck (`cd office && bunx tsc --noEmit`, or whatever `mise run check` runs for office) and say "glyph unverified by test". If a cheap export+test fits an existing test file's pattern, do it; don't refactor main.ts for it.
Commit: `office: an interrupted run gets its own glyph, not the running one (#312)`.

## T6 — Prove the scripts exit 143 on a TERM (no change expected)
Files: none unless it fails; if it does, `scripts/check-main.sh` / `scripts/release-smoke.sh`.
Prove: put a fake `mise` first on PATH that ignores TERM, sleeps, then `exit 1` (stub `git`/fetch is too much — instead copy only the signal part): in a temp script reproduce check-main's shape `trap 'exit 143' TERM; (fake_mise 2>&1 | tee log | grep …); code=${PIPESTATUS[0]}`, send TERM to the bash only, and assert `$?` is 143, with TERM sent to the whole process group too. Record the command + output in the commit/PR text.
- If 143: no script change; say so in the PR (the incident predates cdc3f01).
- If not (bash reports 1): fix at the script — `mise run check … &` / `child=$!` / `trap 'kill $child; wait $child; exit 143' TERM INT` as `tasks/adapters.toml:51` does — and add a `scripts/*.test.sh` case beside `checks-queue.test.sh`'s style.

## Order / sizing
T1 → T2 → T3 → T4 → T5 → T6; each independently committable, ≤2 files + its test. No open work touches schedules.ex, orphans.ex or candidate.ex. Finish: `mise run check`, then `push_branch`.
