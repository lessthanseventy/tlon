# Review: 687-release-smoke-the-port-picker-skips

**Verdict: APPROVE** — branch work/687-release-smoke-the-port-picker-skips @ 05f6c59 (2 commits on 2bdf185).

## The witness statement

`scripts/release-smoke.sh:27`
```
-port="${TLON_SMOKE_PORT:-$((4100 + $$ % 800))}"
+port="${TLON_SMOKE_PORT:-$(smoke_pick_port $((4100 + $$ % 800)))}"
```
`scripts/lib/smoke-build.sh`: `smoke_port_taken` (ss -Hltn, else a /dev/tcp connect) and `smoke_pick_port` (skips 4369 and 4040, steps +1 while a listener is up).

## Spec compliance (tertius' pinned shape, msg #15766)

1. (a) function in `scripts/lib/smoke-build.sh`, which the self-test already sources — yes.
2. (b) 4369 and 4040 skipped outright, then +1 while a listener is up — yes, both checks sit in the one `while`.
3. (c) only the computed port steps; an explicit `TLON_SMOKE_PORT` is the `:-` default's short-circuit and is never passed to the picker; line 58's `4040` refusal and line 61's curl guard still cover it — yes.
4. (d) the pick runs on line 27, `db=tlon_smoke_$port` on line 28 derives from the stepped port — yes.
5. Tests: the three asked for plus 4040 → 4041. `$$` inside the `$(...)` is still the parent's PID, so the base is unchanged.
6. Change kept to these lines: 3 files + pr.md, 40 insertions, 1 deletion.

## What I ran, not eyeballed

- `scripts/cap.sh bash scripts/release-smoke.test.sh` on the branch: exit 0, 13 ok, 0 FAIL (`.logs/20261027T155619-bash-scripts-release-smoke-test-sh.log`).
- The ss path against a live `:gen_tcp.listen(14600)`: taken(14600)=yes, taken(14601)=no, pick=14601.
- The no-ss fallback, under `bash` with ss off PATH: taken(14600)=yes, taken(14601)=no, pick=14601. (Under zsh it reads "not taken" — zsh has no /dev/tcp — but the script runs under bash, so that is not a finding.)
- CHECKS: `mise run check` exit 0 on verify; no `bench_contrast` row, so nothing to contrast.

## Non-blocking (in follow_ups)

7. The self-test's fixed ports 4600/4700/4601 sit inside the smoke's own 4100..4899 pick range; a real smoke running at the same time whose `$$ % 800` lands there fails "a free base is itself" or "steps on". Rare, but a flake with a known cause.
8. The /dev/tcp fallback connects to 127.0.0.1 only, so a v6-only listener reads free on a box without ss (verified: ss path taken=yes, fallback taken=no). ss is on every Linux here; noting it, not blocking on it.
