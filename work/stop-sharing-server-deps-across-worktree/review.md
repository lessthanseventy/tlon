# APPROVE

## Verdict
Approve. Correct, minimal, tested; gate green.

## What it does
`scripts/workline-verify.sh` extracts `copy_deps()` and copies the lead's deps with `cp -rL` instead of `cp -r`. A worktree made before `399c364`/`f5a42ce` still has `server/deps` as a symlink into the shared dir; the old `cp -r` copied the link, so the gate's `mix deps.get` wrote through it. `-L` dereferences, so the fresh checkout gets a real copy and writes stay local.

## Findings
- Correctness: the right fix, and the only deps-copy site in the repo. `check-main.sh` runs `deps.get` in its own real-deps checkout (no copy); `office-drive.sh` copies office config, not deps. No other site needs it.
- Test: the new test extracts the real `copy_deps` from the script via `sed` (not a reimplementation), asserts the copy is not a symlink (`File.read_link` → `{:error, :einval}`), and asserts a write to the copy does not propagate to the shared dir. Both halves of the hazard are covered — not-a-link and no-write-through.
- Surgical: one function, one flag, one test, pr.md. The out-of-scope `node_modules`/`bun.lock` hazard is named in pr.md, with the correct note that the store-backed link is read-only today.
- Gate: verify passed (workline artifact checks exit 0); full `mise run check` green (1901 tests, 0 failed).

## Observation (non-blocking, no ticket)
`cp -rL` dereferences all symlinks, including any internal to `deps`, not just the top-level dir. For post-fix worktrees (real deps dir) this is a behavior change from the old `cp -r`, which preserved internal symlinks. It is strictly more isolated and the gate is green, so not blocking — noted for the record.