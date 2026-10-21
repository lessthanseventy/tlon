# review — work/verify-s-throwaway-checkout-lives-in-tmp

**verdict: approve**

## what it changes

`scripts/workline-verify.sh` moves its throwaway checkout (and the stale-checkout sweep) from `mktemp -d -t tlon-verify-XXXXXX` (→ `/tmp`) to `${XDG_CACHE_HOME:-$HOME/.cache}/tlon-verify`. Three lines of real change plus a load-bearing comment naming the bwrap 9000-arg cap as the reason. A new branch-mode test asserts the gate's `$PWD` is under `$XDG_CACHE_HOME/tlon-verify/`, not `TMPDIR`.

## why it's right

- **The move escapes the seat write roots.** A verify's seeded suite creates hundreds of git repos; under `/tmp` (every seat's write root) each one costs bwrap arguments and overflows the 9000 cap for any seat running concurrently. The cache root is not a seat write root (the banked decision, fact 2875, names this path and excludes `~/.cache/tlon` and `dev_caches` precisely because those *are*). The verify gate passed on the branch — the server's own checkout, not a seat — which is the proof the move works.
- **Sweep semantics preserved.** The flock at line 54 is per-slug, so verifies of different slugs run concurrently. The sweep protects a live checkout two ways — `pgrep -f "$stale"` and the `/proc/*/cwd` lname check — and the second one fires (the gate runs with `cwd` inside `$fresh`). Both are unchanged; only the swept root moved. No cleanup regression.
- **`mktemp -d -p "$vroot" "XXXXXX"` is valid** (≥3 trailing X's, GNU mktemp) and the sweep's `"$vroot"/*/` matches exactly what it creates. The old `tlon-verify-` prefix was a `mktemp -t` template artefact, not a contract.
- **No stranded references.** `grep -rn tlon-verify` over `*.sh/*.ex/*.exs` finds only the two changed lines.
- **The test is genuinely RED-first.** `gate/2` now sets `XDG_CACHE_HOME=ctx.tmp/cache` alongside the existing `TMPDIR=ctx.tmp`; on the old `mktemp` the checkout would land under `ctx.tmp/tlon-verify-*` and `String.starts_with?(cwd, "…/cache/tlon-verify/")` fails. GREEN after the change (19 tests, 0 failed, per the builder; the workline's own verify re-ran the full gate green).

## spec compliance

The workline has no committed spec.md/plan.md (started after a stage whose doc isn't owed); the pr.md states the goal, the RED/GREEN evidence, and the stacking on #502 (the tmp-dir-cleaning fix, which this complements rather than replaces). The change does what the pr.md claims and nothing more — surgical, no adjacent cleanup.

## findings

None blocking. No follow-ups worth filing: the comment is load-bearing (names the cap and the mechanism), not narrative.