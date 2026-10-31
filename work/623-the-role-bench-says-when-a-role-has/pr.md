The role bench no longer says a silent `0/0` when a role has no tasks in the suite.

Closes #623.

## What changed

- **Whole-suite run** (`mise run bench:roles -- --suite canary`, the nightly): a role with no tasks in the suite's tiers is named as skipped (`builder-senior: no canary tier, skipped`), runs nothing and writes no record. It exits 0 for the other roles.
- **Named role** (`--role builder-senior` with no tasks in the suite): an error (`builder-senior: no canary tasks under bench/roles/tasks/senior`), exit 1, nothing run.
- **Promotion:** `senior/s3-epic-parent-law` moves from `full` to `canary`, so `builder-senior` runs in the nightly. It is the fastest passing senior task in the green senior run (70df21c, 6/6: 317.6s, against 420–947s for the rest). All six share the same sourced setup, so wall time decides. The operator chose "promote one".

## How it was checked

- Each behaviour went red first, then green: a runner test for the skipped role, a runner test for the named-role error, and a fixture test that pins the one canary task in the senior set.
- Bench tests: 35/35 green.
- CLI, by hand: the whole-suite path prints the skip line and exits 0; `--role builder-senior` raises and exits 1.
- Full server gate on the head: 2477 tests, 1 failure, `harness_test.exs:212`. That failure is main's red from #617 (ticket #754), not this change. The branch cannot land until #754 closes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
