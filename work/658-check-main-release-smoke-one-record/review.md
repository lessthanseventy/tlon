# Review — 658-check-main-release-smoke-one-record

**Verdict: request_changes** — two one-line fixes in lines this change touched; the three ticket fixes themselves are correct.

Reviewed: fa2bcbe (a76a70d, cc1c2e0, 4d0f039, fa2bcbe on 663324d). `mise run check` green on fa2bcbe (msg #25943).

## What holds

- **One record per scheduled run.** `Server.Schedules.shell/2` passes `TLON_SCHEDULE_RUN=1` in the port's env; `scripts/lib/record-ran.sh` reads it into `scheduled` at source time and `record_ran` returns 0 without posting. Source order verified: check-main.sh sources the lib at line 6 and unsets `TLON_*` at line 34; release-smoke.sh sources at 25 and unsets `TLON_|RELEASE_` at 41. Tests: schedules_test (marker visible to the script), record-ran.test.sh (sourced with the marker, unset, then called: no POST), and that test is in the gate (tasks/server.toml:200).
- **A red nightly names its test for any suite.** `failures()` moved verbatim to `scripts/lib/failures.sh`; workline-verify.sh and check-main.sh both source it; workline_verify_script_test sources the lib instead of sed-lifting the function. One pattern on the machine, as the brief asked.
- **Hex home beside the tree.** `"$dir.hex"` / `"$fresh.hex"` in all three seed_hex_home callers, removed in each EXIT path and by both sweeps. check_main_script_test's new case asserts `git status --porcelain` is empty in the gated checkout and a `main-??????.hex` sibling exists (red on the old script).

## Findings

1. **smoke-sweep.sh:15–24 treats the `.hex` sibling as a stale tree of its own.** `for stale in "${TMPDIR:-/tmp}"/tlon-smoke/*/` now yields `XXXXXX.hex/`. It has no `.lock`, so it falls to the else branch: removed once its mtime is 120 minutes old. seed_hex_home sets that mtime at seed (two file copies); Hex later rewrites cache.ets in place, which does not touch the directory's mtime. A run alive past two hours (`TLON_SMOKE_HOLD` ttl is 7200; or a long build-lock wait plus build) has its Hex home swept by a concurrent sweep. After the build nothing reads HEX_HOME, so the harm is small, but workline-verify.sh:83 got exactly the guard this sweep lacks, and it is one line:
   ```
   -  stale="${stale%/}"; [ -d "$stale" ] || continue
   +  stale="${stale%/}"; [ -d "$stale" ] || continue
   +  # a tree's Hex home goes with its tree
   +  case "$stale" in *.hex) continue ;; esac
   ```
2. **record-ran.sh:9's skip line begins "not posted:".** That is check.sh's phrase for a tlon/check it refused (`not posted — the tree has uncommitted…`), the line whose appearance in an alert tail is what #658 chased. It is now the last line of every scheduled nightly's output. Say what happened:
   ```
   -  [ -z "$scheduled" ] || { echo "not posted: the schedule records this $1 run"; return 0; }
   +  [ -z "$scheduled" ] || { echo "recorded by the schedule: $1 run"; return 0; }
   ```

## Noted, not findings

- check-main's red report now prints name + file:line (10 lines, 160 cols) where the old grep printed the 14-line block with the assertion. The brief asked for the one shared pattern; the log path remains in the output.
- `TLON_SCHEDULE_RUN=1` reaches every scheduled script, not only the gates. Harmless and the simplest place to set it.
