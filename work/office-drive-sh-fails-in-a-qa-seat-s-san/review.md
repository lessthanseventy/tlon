APPROVE

The fix is correct and well-scoped. `office-drive.sh` resolves the real bun binary via `bun -e 'process.execPath'` at drive startup — while `XDG_STATE_HOME` still points at the operator's mise trust db — then runs that binary directly in the TUI's tmux session, so the shim's trust lookup (which fires under the throwaway `XDG_STATE_HOME`) is never hit. This covers both the sandbox case and the worktree case (#583: the parent checkout's `mise.toml` is never consulted because mise is never invoked at all). Resolving from `$root/office` with `process.execPath` rather than `mise which bun` keeps boxes without a mise-managed bun working — a deliberate choice, per the builder's note. The single-quotes around `'$bun'` in the session command correctly guard paths with spaces.

The stderr-exit-1 fix closes the false-green (the drive exited 0 even when the TUI never started). I traced every caller; all are safe with the change:
- `office/test/drive/run.sh` — comment updated; still greps `=== stderr`, and `pipefail` now propagates the drive's exit 1 through the `tee` pipeline.
- `scripts/release-smoke.sh` — ignores the drive's exit code (checks screen content via `expect`); the `=== stderr` marker doesn't collide with the `=== after:` extraction. No regression.
- `Server.Smoke.drive/3` — pattern-matches `{out, _code}`; exit code ignored. No regression.

Tests are red-first stub tests: a fake `bun` shim that fails the way mise does under a set `XDG_STATE_HOME`, and a fake real binary. Test 1 verifies the drive runs the resolved binary (output has "started", no "not trusted"); test 2 verifies stderr fails the drive (exit 1, "boom" printed). Commit trailer matches the builder's model (sonnet-5-5). Verify evidence is solid: the new test file + release-smoke script tests (27/27), the full gate (874 office, 0 fail), and a real drive from the worktree showing HOME, exit 0.

Non-blocking note: `MISE_TRUSTED_CONFIG_PATHS='$root'` is still exported into the TUI session (line 47) but is now dead — the real bun binary bypasses mise entirely, so the trust list is never read. Harmless (belt-and-suspenders); not worth a ticket, but a future cleanup could drop it.