# Review — 658-check-main-release-smoke-one-record

**Verdict: approve** — round two; both findings and the follow-up from 51c8091 are fixed, test-first, in the lines named.

Reviewed: 36fe31b (d4ddbf8, 36fe31b on 51c8091; the four build commits a76a70d, cc1c2e0, 4d0f039, fa2bcbe on 663324d reviewed in round one). Verify's `mise run check` passed on 36fe31b (CHECKS 2026-11-01T00:11:15Z, exit 0). No bench_contrast row in CHECKS.

## Round-one findings, checked

1. **smoke-sweep.sh treated the `.hex` sibling as a stale tree.** Fixed at smoke-sweep.sh:18: `case "$stale" in *.hex) continue ;; esac`, the guard workline-verify already had. Test (release_smoke_script_test): a live run holding its lock, its Hex home touched to 3 hours old, survives `sweep(ctx)`; without the guard the mtime rule at line 23 removed it.
2. **record-ran.sh's skip line began "not posted:".** Fixed at record-ran.sh:9: `recorded by the schedule: $1 run`. The last line of a scheduled nightly now says what happened, not check.sh's refusal phrase.

Follow-up (orphaned Hex home under the verify cache): fixed at workline-verify.sh:83, `*.hex) [ -d "${stale%.hex}" ] || rm -rf "$stale"; continue`. Test: `the sweep removes a Hex home whose tree is gone` (refute File.exists? after the gate).

## What holds from round one

- One record per scheduled run: `TLON_SCHEDULE_RUN=1` from `Server.Schedules.shell/2`; record-ran.sh reads it at source time, before check-main.sh (line 34) and release-smoke.sh (line 41) unset `TLON_*`.
- A red nightly names its test for any suite: one `failures()` in scripts/lib/failures.sh, sourced by workline-verify.sh and check-main.sh.
- Hex home beside every gated tree; check_main_script_test asserts `git status --porcelain` is empty in the gated checkout.

## Noted, not findings

- Verify's tail still ends "tlon/check: not posted — the tree has uncommitted or untracked changes, or HEAD moved". Every kept verify log since #328 ends the same way, before any `.hex` existed, so it is not this change's doing; filed as its own ticket (verify never writes check.sh's green-tree cache, so a landing re-runs the suite).
- smoke-sweep skips an orphaned `.hex` for good where workline-verify's now removes one. The window is a SIGKILL between two paths of a single `rm -rf` (release-smoke.sh:50, smoke-sweep.sh:25), and tlon-smoke lives in /tmp, which a reboot clears; the verify cache does not. Not worth a round.
