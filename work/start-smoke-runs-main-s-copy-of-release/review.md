# approve — start_smoke runs main's release-smoke.sh

## verdict

**approve.** The fix is correct, minimal, and matches the #10065 scope. Commit `52c3a79` changes `Server.Smoke.script/0` to resolve through a new `main_root/1`, so the held smoke runs main's copy of `scripts/release-smoke.sh` instead of the `.release` build dir's stale copy.

## what I verified

- **The mechanism is right.** `.release` is a git worktree, not a plain build dir: `.release/.git` is a 59-byte worktree pointer, and `git -C .release rev-parse --path-format=absolute --git-common-dir` returns `/home/andrew/projects/tlon/.git` (exit 0). `Path.dirname/1` of that is `/home/andrew/projects/tlon` — the main checkout. So `main_root(tlon_root())` maps the service's build dir to main, which is exactly the #10065 ask ("resolve to the parent of `.release`'s git-common-dir").
- **It matches `scripts/run-from-root.sh`** — same `--path-format=absolute --git-common-dir` → parent. Consistent with the repo's existing root-checkout pattern.
- **The `cd` is fixed by the same change.** `Jobs.Smoke` calls `script_root(Server.Smoke.script())` = `script |> Path.dirname() |> Path.dirname()`. With `script/0` now returning `<main_root>/scripts/release-smoke.sh`, `script_root` derives `<main_root>`, so the job's `{:cd, …}` also lands in main. Both the script path and the cd resolve to main through the one change in `script/0`. Nothing left to touch in `Jobs.Smoke`.
- **`tlon_root()` is used only as the starting point**, not as the script path — the scope said don't use it as the path; feeding it to git as the `from` dir is the intended mechanism (that's what run-from-root.sh does from its own location). Not a violation.
- **Test is adequate.** `smoke_script_test.exs` builds a synthetic repo + worktree and asserts `main_root(worktree) == main` and `main_root(main) == main` — i.e. a worktree resolves to its main checkout, and main to itself. RED→GREEN reported; `Jobs.Smoke` 6/6. `main_root/1`'s `from` parameter is the seam the test needs (synthetic repo, not the real one), not speculative abstraction.
- **No blocking bugs.** `main_root/1`'s `{out, 0} = System.cmd(...)` raises a MatchError if `from` isn't a git repo. In the live service `from` defaults to `tlon_root()` = `.release`, which is always a worktree, so this can't fire there; and a loud crash is strictly better than the silent stale-copy bug it replaces. Acceptable.

## follow-ups (non-blocking)

- **No `pr.md` committed.** Build's exit owed one; publish's `body/0` falls back to the plan/spec heading when `pr.md` is empty, so this doesn't block landing — but the builder's own one-line account of the change is absent from the PR body.
- **Test file name collides.** `smoke_script_test.exs` sits next to `release_smoke_script_test.exs`; near-identical names, easy to grab the wrong one. `smoke_test.exs` would read cleaner for `Server.Smoke`'s own tests (the existing file tests the bash script, this one tests the Elixir locator).

Out of scope (#489, #494) correctly untouched.