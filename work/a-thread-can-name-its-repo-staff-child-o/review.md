# Review — a-thread-can-name-its-repo-staff-child-o @ d2869a8 (round 6)

**Verdict: approve.** The three round-5 findings (a809135) are fixed on the branch in the ruled shapes, verify is green on exactly this head (`mise run check` exit 0 at 03:23Z, evidence `workline:a-thread-can-name-its-repo-staff-child-o:verify`), and the one follow-up I carried from round 5 was folded into d2869a8, so nothing is left open. Read: `git diff a809135..d2869a8 -- . ':!work/…'` (worktree.ex, profiles.ex, smoke.ex, worktree_test, profiles_main_root_test).

## Findings from round 5, checked

**1. Fixed — a sibling's own `core.hooksPath` is refused, never overwritten.** `set_hooks_path/2` reads `config --get` first: `{_, 1}` (unset) → sets tlon's; equal → `:ok`; anything else → `{:error, "<repo> has its own core.hooksPath (<value>); not pointing it at tlon's"}`. The `with` in `point_hooks_at_tlon/1` means `ensure` returns that error before `ensure_checkout` runs. The test is the witness:

```
{_, 0} = git.(["config", "core.hooksPath", "elsewhere"])
assert {:error, msg} = Worktree.ensure(repo, "hooked")
assert msg =~ "elsewhere"
assert String.trim(out) == "elsewhere"
refute File.exists?(Worktree.path(repo, "hooked"))
```

The idempotency half of the original test is kept (second `ensure` with tlon's value → `:ok`); the overwrite assertion is gone. `git/2` is `stderr_to_stdout: true` through the pre-existing `:git_cmd` seam (on main at worktree.ex:498), so the exit-1 branch is `--get`'s unset case and nothing else.

**2. Fixed — `Profiles.main_root/1` returns `{:ok, root} | {:error, out}`.** `stderr_to_stdout`, output sliced to 200. Worktree passes the error through; `Smoke.script/0` unwraps with `{:ok, root} = Server.Profiles.main_root()` (d2869a8 replaced the `elem(…, 1)` that would have built a path from git's error text). New test: a non-repo tmp dir returns `{:error, _}`, stamped with `System.pid()` after the first verify caught the unique_integer-only name. Worktree's moduledoc "never a raise" now holds in `ensure` for real.

**3. Fixed — the tlon-own-checkout no-op is pinned.** The new test runs `ensure` on `File.cwd!()` (`server/`, inside tlon's checkout) with every `git/2` call stubbed; `main_root/1` uses `System.cmd` directly, so the common-dir comparison is real while nothing is written. A broken comparison would send `config --get` to the stub and trip `refute_received`. It leaves `server/.worktrees/own-noop-N/.git` for the test's life; `.worktrees/` is ignored and `on_exit` removes it.

## Not findings
- `point_hooks_at_tlon` returns `main_root(repo_path)`'s raw git text on a non-repo `repo_path`, with no "could not" prefix. Unreachable: `ensure` refuses `:not_a_repo` at line 64 before it gets there.
- The three ✗ proof rows (intent/spec/plan not committed) are the docs, not the code; this child never had them on the branch. The operator's call at `approve 420`, as noted in round 4.
- No `bench_contrast` row among the CHECKS.
- Branch is 11 commits on top of origin/main at b8fffdf; the diff is 15 files, +354/−32, all under `server/` plus the workline's own docs.