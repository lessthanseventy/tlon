# Review — #460 push_branch takes a named work/<caller>-* branch

**Verdict: approve.** Head ffbd0c9 (2 commits on 3cdc19c), 57 lines across 7 files. Spec (tertius, msg #15103) met point by point; nothing widened beyond it.

Evidence: the server's `mise run check` row at 09:46Z passed on ffbd0c9 (CHECKS). I read the diff and the seams it touches; I ran nothing myself.

## Findings

1. **Authorization is where the spec put it, and nowhere else.** `Publish.own_branch/2` admits only `"work/#{agent}-"` with at least one byte after the prefix. `work/uqbar-`, `work/uqbar`, `work/uqbarx-fix`, `work/hronir-fix`, `main` and `uqbar-fix` are each refused by the test. `agent` is the token's `sub` (`Identity.from_frame`), a plain handle string, so the guard clause matches for a real caller and a missing `sub` falls to the refusing clause. A named branch still goes through `push_branch/3`'s `\Awork/[a-z0-9][a-z0-9-]*\z`, so case or path tricks after the prefix are refused downstream.

2. **No collision with workline branches.** A thread branch is `work/<ticket>-<slug>` and a named one is `work/<handle>-<name>`; no handle is numeric and no roster handle contains a hyphen, so neither prefix can read as the other.

3. **The one caller it was built for reaches a repo.** Thread 269 has no project; `Projects.repo_for_thread/1` falls to the workspace's first repo-bearing project, so `Server.repo_for_thread` returns the tlon checkout, not `:no_repo`.

4. **Hooks and plugin gate untouched, as specified.** The new commits_test proves the pre-commit passes `work/uqbar-x` with `TLON_THREAD=269` set.

5. **Docs in the same change.** Uqbar's role text names the whole door (switch -c in a scratch, push_branch with `branch:`, review_branch, land); AGENTS.md's push_branch sentence names it. The AGENTS.md edit makes this a limit gate: the operator's call, as tertius said.

6. **bench_contrast** reads `unmeasurable` (AGENTS.md is never loaded by the bench). Not green, not a regression: no finding, no habit.

## Not blocking

- `Server.MCP.Tool.PushBranch`'s moduledoc still says it pushes "the caller's own thread branch, work/<slug>"; `push_branch/3`'s @doc says "Push one thread's branch". Both are now a half-truth. Listed as a follow-up.
- The `branch:` path of the tool has no tool-level test; the rule is tested in Publish and the wiring is two lines I read. Listed as a follow-up.
