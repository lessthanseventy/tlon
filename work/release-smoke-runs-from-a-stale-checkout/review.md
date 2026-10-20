APPROVE

release:smoke now runs main's script, not the launching checkout's (#273)

Verdict: approve. Minimal, correct, test-first; verify passed (`mise run check` exit 0 on branch).

What shipped
- `scripts/run-from-root.sh`: execs the shared root checkout's (main's) `scripts/<x>` instead of the launching worktree's own. Resolves the root via `git rev-parse --path-format=absolute --git-common-dir`, which for a worktree points at the root's `.git`, so `/..` is the root working tree — and for the root checkout itself too. Sound. `set -euo pipefail`; `script="$1"` under `set -u` fails fast if invoked bare, but only `tasks/release.toml` calls it, always with the arg.
- `tasks/release.toml`: `release:smoke` now runs `run-from-root.sh release-smoke.sh`. The nightly "smoke" schedule in `pm.ex:45` already runs `mise run release:smoke`, so schedule 4 goes through the wrapper too — no pm.ex change needed.
- `AGENTS.md`: documents the wrapper and the rebase-it-yourself caveat for checkouts too old to carry it. Docs in sync with code.
- `server/test/server/run_from_root_test.exs`: real RED→GREEN — a worktree on an old base (`old-script`) running the wrapper prints the root's `new-script work/x`. Proves the mechanism against git itself, not self-consistency.
- `server/test/server/canvas_paint_test.exs`: `receive.autogc=false` on the scratch bare remote, so `on_exit`'s `rm_rf` no longer races a detached `gc --auto`. Resolves #430 (hit during verify); named in pr.md.

Spec compliance — operator option (b) = (a) + run-fresh wrapper
- Nightly schedule runs release:smoke via main's copy: the schedule pre-exists (`pm.ex:45`); the wrapper routes it. ✓
- Run-fresh wrapper: shipped. ✓
- "List stale seats to rebase": done informationally this session (13/16 worktrees differ from origin/main, learning #2198); the rebase is the owners'/Andrew's call (learning #2220), not shipped code — matches the operator's framing.

Non-blocking notes
- The PR bundles #430 (a test-infra flake fix) with #273. Small, transparent in pr.md, and it was blocking verify; fine to ship together, not worth splitting.
- `run-from-root.sh` trusts the invariant that the root checkout is kept at main (AGENTS.md says so; the service reads its HEAD). It does not re-verify that — correct, since re-verifying would duplicate `fresh-script.sh`'s job, which main's `release-smoke.sh` already runs once the wrapper execs it.

No follow-ups.