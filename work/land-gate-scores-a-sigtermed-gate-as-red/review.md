# Review: land-gate-scores-a-sigtermed-gate-as-red @ 2936bd9

**Verdict: request_changes.** The change does what #693 asks on both paths, and the gate is green on it (CHECKS: `mise run check` exit 0). One correctness hazard in the change's own lines, with a two-line fix.

## 1. The phrase match is unanchored, and the branch's own test puts the phrase in a red run's output (blocking)

Both matches read the whole output for the substring:

    land.ex:    if code > 128 or String.contains?(out, @termed) do
    verify.sh:  case "$out" in *"SIGTERM received - shutting down"*) … exit 143 ;; esac

The new test holds that exact phrase in its input. When `gate_result/1` regresses, ExUnit's match-failure report prints the input back. I ran the shape of that failure (`mise exec -- elixir` on a one-test file with a red `gate_result` return); the report was:

    right: {:error,
            "the full check on main with this branch is red (exit 1): [server:check] SIGTERM received - shutting down\n** (EXIT from #PID<0.95.0>) shutdown"}

So the one test that guards this fix cannot go red as a red: on verify, `run_gate` sees the phrase, exits 143 with nothing recorded, `Verify.finish` retries three times and then hands the sheriff "verify could not run"; on a landing, `gate_result` scores it interrupted, Oban retries, and the last attempt bounces it as "cut off". A regression is reported as the service going down. That is the misread this ticket fixes, turned around.

Nothing else in the suite emits the phrase: on main it appears nowhere in the repo, and the tests that send TERM (`orphans_test`, `schedules_test`'s `kill -TERM $$`, the office's kill-server) TERM shells and holder processes, not a BEAM.

Fix: match the BEAM's notice as a whole line. In the real log the phrase ends its line (`.logs/verify-441-…log:3884`: `[server:check] 22:16:22.201 [notice] SIGTERM received - shutting down`); in a failure report it is followed by `\n** (EXIT` on the same physical line.

    --- a/server/lib/server/jobs/land.ex
    +++ b/server/lib/server/jobs/land.ex
    -  @termed "SIGTERM received - shutting down"
    +  # the BEAM's notice ends its line; the same words quoted in a failing test's report do not
    +  @termed "SIGTERM received - shutting down"
     …
    -    if code > 128 or String.contains?(out, @termed) do
    +    if code > 128 or Enum.any?(String.split(out, "\n"), &String.ends_with?(&1, @termed)) do

    --- a/scripts/workline-verify.sh
    +++ b/scripts/workline-verify.sh
    -  case "$out" in *"SIGTERM received - shutting down"*) echo "workline-verify: '$name' was cut off by SIGTERM" >&2; exit 143 ;; esac
    +  if printf '%s\n' "$out" | grep -q 'SIGTERM received - shutting down$'; then
    +    echo "workline-verify: '$name' was cut off by SIGTERM" >&2; exit 143
    +  fi

And a second test case that pins the distinction: an `out` whose only occurrence of the phrase is inside a quoted string (the report shape above) at exit 1 must still be `{:error, binary}`, red.

(A regex would do the same, but a `~r` in a module attribute is a trap on OTP 28; the split-and-ends-with form has no such edge.)

## 2. Read, no finding

- Verify path: `run_gate`'s `exit 143` runs before `record-verify`, so nothing is recorded; `Verify.finish/5` ignores the exit code and reads "recorded nothing" as retry (max 3, then the sheriff). The `trap cleanup EXIT` still drops the throwaway checkout. `exit` inside the function under `run_gate … || fail=1` exits the script, not the list. Correct.
- Landing path: in `WORKLINE_GATE` mode the script exits 143 first, so `gate_result/1` takes the `code > 128` branch; the string branch in land.ex is reached only when the root checkout's script copy is older than the release. Belt and braces, and the two must keep agreeing on the phrase. Acceptable; noting it.
- The builder said RED was unobserved (`run_verb` "Internal error"). By main's clause (`code > 128` only, else the red string) the new test is red there by construction; the verify gate shows it green here.
- pr.md is honest about the script path being unexercised end to end. Finding 1 is the one way to exercise it that the branch does cover, and it is the case that misfires.