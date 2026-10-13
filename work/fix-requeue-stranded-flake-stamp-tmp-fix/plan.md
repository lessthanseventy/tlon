# Plan — stamp /tmp test fixtures with the pid (ticket #329)

Hypothesis, NOT confirmed (the failing assertion was never captured): two concurrent gates are two
BEAMs whose `System.unique_integer` sequences restart, so both can pick `/tmp/approval-N`; one's
`git init`/`on_exit rm_rf!` wipes the other's fixture repo mid-test. Do NOT inject a clock (refuted:
the approval's own job always satisfies `inserted_at >= at`); shared test DB is refuted too (private
`tlon_test_<name>_<hash>` per worktree). Say "unconfirmed" in pr.md.

Scope note: the ticket lists 6 unstamped fixtures; `grep` finds ~38 sites in server/test using
`tmp_dir!()` + `unique_integer` without `System.pid()`. Same bug, same one-line fix, so Task 3 stamps
them all mechanically and Task 2 guards against regression. All in server/test; no lib change.

Run everything from `server/` via mise (OTP 28): `mise exec -- mix test <file>`.

## Task 1 — the honest repro (no commit; evidence for pr.md)
Show the collision, don't assume it.
1. From two worktrees (private DBs) run concurrently:
   `cd server && mise exec -- mix test test/server/workline_test.exs --seed 0` in both.
2. In a third shell: `inotifywait -m /tmp -e create | grep approval-` (or `watch -n0.1 ls -d /tmp/approval-*`).
   Done = you saw the same `/tmp/approval-N` path used by both runs, OR a failure of the
   `requeue_stranded` test in one run. If not reproducible after ~5 attempts, say so in pr.md and
   proceed (the fix is still correct: the path is provably process-unique after it).

## Task 2 — guard test, written first (RED)
Create `server/test/server/tmp_fixture_stamp_test.exs`:
```elixir
defmodule Server.TmpFixtureStampTest do
  use ExUnit.Case, async: true

  # Two gates at once are two BEAMs whose unique_integer sequences restart, so a /tmp fixture named
  # only by unique_integer can collide and one run's rm_rf wipes the other's repo (ticket #329).
  test "no test names a tmp fixture by unique_integer alone — stamp it with System.pid()" do
    self_path = Path.expand(__ENV__.file)

    offenders =
      Path.wildcard(Path.expand("../**/*_test.exs", __DIR__))
      |> Enum.reject(&(&1 == self_path))
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} ->
          line =~ "System.tmp_dir!()" and line =~ "System.unique_integer" and
            not (line =~ "System.pid()")
        end)
        |> Enum.map(fn {_, n} -> "#{Path.relative_to_cwd(file)}:#{n}" end)
      end)

    assert offenders == []
  end
end
```
Verify RED: `mise exec -- mix test test/server/tmp_fixture_stamp_test.exs` fails listing ~38 sites
including `workline_test.exs:751`. Commit: `test: guard — tmp fixtures must carry the pid (#329)`.

## Task 3 — GREEN: stamp them (one mechanical commit)
Every offending line has the shape `System.tmp_dir!(), "<prefix>-#{System.unique_integer([:positive])}`
(some end in `.json`/`.exs`; `arbiter_tmux_test.exs:347` uses a `sock` variable and is not matched —
leave it). From `server/`:
```
grep -rlE 'tmp_dir!\(\).*unique_integer' test --include=*_test.exs \
 | grep -v tmp_fixture_stamp_test \
 | xargs sed -i -E '/System\.pid\(\)/! s/(tmp_dir!\(\), "[^"#]*)#\{System\.unique_integer/\1#{System.pid()}-#{System.unique_integer/'
```
Check: `git diff --stat` touches only test files; spot-check `workline_test.exs:751` reads
`"approval-#{System.pid()}-#{System.unique_integer([:positive])}"`. Lines the sed misses (different
quoting) show up as guard-test offenders — hand-edit each the same way.
Done = `mise exec -- mix test test/server/tmp_fixture_stamp_test.exs` green, then
`mise exec -- mix test test/server/workline_test.exs` green (5/5 — the per-approval describe included).
Commit: `test: stamp /tmp fixtures with the pid so concurrent gates can't collide (#329)`.

## Task 4 — gate and hand off
`mise run check` (one at a time; runs via Menard, unsandboxed). Done = exit 0, record_check.
pr.md: state cause as unconfirmed hypothesis, what Task 1 showed, "Fixes issue #34" is from the
ticket intake — keep. Then push_branch / advance_stage.
