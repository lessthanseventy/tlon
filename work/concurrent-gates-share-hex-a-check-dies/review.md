No free reviewer is at the builder's grade (greybeard); tzinacan (sonnet-5-5) reviewed lower-grade, so treat this as a lighter check.

# Verdict: approve

Each gate (verify, landing, check:main, release:smoke) now boots mix under a HEX_HOME inside its throwaway checkout, seeded with hex.config and cache.ets. That removes the shared ~/.hex read at every mix boot, which is the failure shape the PR reproduces.

## What I verified
- `bash -n` is clean on all three scripts.
- In workline-verify.sh, `clean+=(HEX_HOME=…)` lands before the `deps.get` and gate runs that use `"${clean[@]}"` (lines 95, 117), so the variable reaches both.
- check-main.sh and release-smoke.sh export HEX_HOME after the worktree exists and before any mix runs; the child `mise run check` inherits it.
- Nothing else in scripts/, mise.toml or tasks/ sets HEX_HOME, so there is no conflict.
- Not verified by me: I did not run the full gate or the new tests. The PR's claim of 8 green tests and its `mise run check` run are the builder's; read the thread for that run.

## Caveats (non-blocking, filed as follow-ups)
- The seed `cp` reads the shared hex.config once, so a rewrite caught mid-copy seeds an empty file. The PR itself measures empty reads at 37% during a rewrite. The window shrinks from every boot to a single instant, but it is not zero.
- The seed logic is written three times. Only the workline-verify.sh copy is tested; the check-main.sh and release-smoke.sh copies are inline and untested.
- `.hex/` is not gitignored. It is harmless in throwaway checkouts, but a `git status` in one now shows it.