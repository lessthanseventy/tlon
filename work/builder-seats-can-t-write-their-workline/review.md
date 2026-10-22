approve — reviewed by tzinacan (no free reviewer was at the builder's greybeard grade); no blocking findings.

## What it does
`launch.sh` adds `$PWD`, `git rev-parse --absolute-git-dir` and `--git-common-dir` (both `--path-format=absolute`) to the sandbox `allowWrite` at launch, deduped after the profile's compiled-in entries. Fixes #497: in the service the profile's "tlon checkout" entry compiles to `tlon/.release`, so a seat in a linked worktree had only its cwd as a write root — it could edit but not commit, because a commit writes the worktree's gitdir and the common `.git`, both outside the worktree. The stale "tlon's own checkout" comment in `Server.Profiles` is corrected. `_build` rides on `$PWD`. #566 (panes that boot without `TLON_CWD`, so `$PWD` is `/run/user/1000`) is correctly left open and called out in pr.md.

No spec.md/plan.md on this workline (started at build); reviewed against pr.md and #497.

## Verified
- Full `mise run check` green (verify evidence on the thread); `adapters:claude-code:check` 86 pass / 0 fail.
- The new `launch.test.ts` case builds a real repo + linked worktree, dry-runs the launcher with `cwd=worktree`, and asserts `allowWrite == ["/tmp", worktree, <repo>/.git/worktrees/wt, <repo>/.git]` — red before (three paths missing), green after. Sound pinning test.
- I re-ran the jq dedup by hand: `index([$d])` finds `$d` as a one-element subarray, so the common-dir duplicate (absolute-git-dir == git-common-dir in a non-worktree checkout) IS collapsed. (Latent edge: an element matching index 0 is treated as not-found, since 0 is falsy in jq, so a positional equal to the *first* existing entry would duplicate. Never happens for a workline seat — its `$PWD`/gitdirs aren't in the profile list — and a duplicate allowWrite entry is harmless to bwrap regardless. Not worth a follow-up.)

## Security
Adding the common `.git` grants write to the shared object store and shared refs (`refs/heads/*`, including `main`) of the repo's main checkout. This is inherent to linked-worktree commits (objects live in the common dir) and matches the existing trust model: coworkers are autonomous-but-cooperative, the sandbox is a narrow last line rather than an adversarial defense, and a seat's own pushes are already refused by the pre-push hook (the server pushes the branch). Claude Code's sandbox protects the sensitive git files (`config`/`config.lock`) under any write root. Not a new exposure class — the repo root was already a write root in dev. Accepted.

## Follow-ups (non-blocking)
none.