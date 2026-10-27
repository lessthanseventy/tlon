# Review: 687-release-smoke-the-port-picker-skips (round 2)

**Verdict: APPROVE** — branch work/687-release-smoke-the-port-picker-skips @ e255524 (3 commits on 2bdf185, plus my round-1 review.md).

## What changed since 7b23201

One commit, e255524, touching only `scripts/release-smoke.test.sh`. `git diff 7b23201..HEAD -- . ':!work/687-…'` is exactly the diff I sent back in msg #15796: the free-base and listener cases move to 14700/14600, the two skip cases become relational (`$p -gt 4369`/`4040` and `! smoke_port_taken "$p"`), and a comment says why the fixed ports stay out of 4100..4899 and 4041. `smoke-build.sh` and `release-smoke.sh` are unchanged from round 1.

## Findings from round 1

1. Fixed ports in the smoke's range / server:dev's 4041 (the send-back) — **fixed** by e255524, as prescribed. daneri reports 13 ok with rival listeners on 4700/4370/4041 (msg #15799); I did not re-run the rival case this round.
2. /dev/tcp fallback and v6-only listeners — **dropped** by my ruling in msg #15794: ss is on every box that smokes, and the fallback is no worse than the old behaviour. Not open.

## What I ran

- `scripts/cap.sh bash scripts/release-smoke.test.sh` on the branch at e255524: exit 0, 13 ok, 0 FAIL (`.logs/20261027T161422-bash-scripts-release-smoke-test-sh.log`).
- CHECKS: `mise run check` exit 0 on this round's verify (22:12:53Z); no `bench_contrast` row, nothing to contrast.
- Tree clean at HEAD.

## Nit, not a finding

`work/687-…/pr.md`'s "Checked:" line still reads "4369 → 4370; 4040 → 4041"; the tests now assert "above the skipped port and free". The description is slightly stale, the code is not. Nobody acts on it within a week, so no follow-up.