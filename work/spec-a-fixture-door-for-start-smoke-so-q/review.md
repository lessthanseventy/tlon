# Review — #494 fixture door for start_smoke

No free reviewer sat at the builder's grade (greybeard), so tzinacan leads this review.

**Verdict: approve.**

The change is spec-faithful, surgical, and tested. Four build commits map one-to-one to the plan's
four tasks; the gate is green (`menard run check --in server` → 1938 tests, 0 failed; the full
`mise run check` passed on the branch per the verify record). The real branch diff is 468 insertions
across 13 files — the large deletion count in `git diff origin/main` is main having advanced since
the branch point, not this work.

## Spec compliance (§2–§4, §6)

- §2 closed catalog `Server.Smoke.Fixtures` (`name => (-> :ok)`), first entry `tool_denied_need`;
  names use the flag grammar; `names/0` lists them. ✓
- §3 only a qa seat, through `start_smoke`'s new `fixtures` arg (`{:list, :string}`); same
  `QASmoke.thread/2` gate, no new permission, no HTTP route, seeded once at start. ✓
- §4.1 `Smoke.start/5` grammar-checks names only; carries `fixtures` into job args; omits when empty
  via the existing `Map.reject`. ✓
- §4.1 `Jobs.Smoke` exports `TLON_SMOKE_FIXTURES` (space-joined), beside `TLON_SMOKE_FLAGS`. ✓
- §4.2 `release-smoke.sh` runs the rpc after the flags loop and before the drive; unknown name or
  any error fails the smoke (`fail "fixture …: not seeded"`). ✓
- §4.3 `Fixtures.apply` refuses any db not `tlon_smoke_*` (nil included), before the catalog lookup,
  so it cannot seed the live db even if called by mistake. ✓
- §6 every verify item has a test (`fixtures_test.exs`, `jobs/smoke_test.exs`,
  `release_smoke_script_test.exs`). ✓

## Notes (non-blocking, not filed)

- The `Kernel.apply/2` clash is handled with `import Kernel, except: [apply: 2]` — clean, and the
  module never needs `Kernel.apply/2`.
- The fixture backdates `created_at` 60s and the test setup dismisses `Rollout.pending()` — the
  builder carried forward the lesson from the #89 needs_test flake (fact #849).
- `TLON_SMOKE_FIXTURES` is read at line 25, before the line-31 `TLON_*` unset the plan flagged. ✓
- `$fx` in the rpc string is safe because the MCP path grammar-checks names; a direct
  `release:smoke` with a hand-set `TLON_SMOKE_FIXTURES` trusts the operator (local, scratch db) —
  the plan explicitly accepted this.
- `profiles.ex` (the QA role brief) gained a docstring line for `fixtures`; not named in the plan
  but found by its `grep -rn start_smoke … server/AGENTS.md`, and landed in the release-smoke commit
  as the plan said. In scope.

## Not verified

A real `release:smoke` with fixtures — the sandbox can't run it. The spec names QA's live run as
the proof, and that is the QA gate's job, not this review's.