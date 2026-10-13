# release:smoke of a local work/<slug> ref survives a failed fetch

Closes #176.

`scripts/release-smoke.sh` failed with "can't fetch origin" whenever origin could not be fetched, even when the smoke target was a local `work/<slug>` ref. A local ref lives in the shared `.git`, so the fetch was never needed. In a sandboxed seat with no ssh access, that made the prescribed QA smoke impossible.

Now a failed fetch is fatal only when the target is not a local branch. For a local ref the script prints a warning and resolves the ref as is. `origin/main` (the default) still fails as before, since it needs the fetch.

Checked:
- New tests in `server/test/server/release_smoke_script_test.exs` run the smoke against a repo whose origin can't be fetched. A local `work/feature` ref gets past the fetch; the default target still fails with "smoke FAILED: can't fetch origin". The first test went red before the fix.
- `mise run check` on the workline worktree: exit 0. Server 1579 passed; adapters and office green; names and manual checks green.
