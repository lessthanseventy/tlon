# Review: pre-commit fences the lobby (#561)

**Verdict: approve.** One commit, fdbd32f on d6b0c66. The fix is the narrowed option (a) from the tech lead's read, and nothing outside it. Verify's full check passed on the branch.

## What I verified

1. **The fence fires only where it should.** `scripts/git-hooks/pre-commit` refuses when `TLON_LOBBY` is set AND `$branch = work/t$TLON_THREAD`, before the existing `work/*` allow. A lobby pane's own branch is `work/t<root id>`: `Worktree.name_for(%{id: id})` gives `t#{id}` and `branch/1` prefixes `work/`, and the root thread never carries a slug (Workline.promote refuses it), so the string compare is exact. A lobby pane committing in `.worktrees/<slug>` sees `work/<slug>`, falls through to the allow, and that is the path the refusal message points at. Detached HEAD in the lobby still hits the old refusal. A human terminal has neither variable.
2. **The export is per-workspace root, not "thread 1".** `lobby_export/1` leans on `Channel.root_machine_thread?/1`, which compares against `machine_thread(thread.workspace_id)`. A second workspace's lobby is fenced too, on its own id. The export rides `mint_and_export`, which every pane launch goes through (switchboard wake spawn, crew join, coordination's lead join all call `Spawn.join`), so there is no launch path that skips it.
3. **Allowed cases are tested as carefully as the refusal**, as the brief asked: lobby pane on `work/uqbar-x` and a workline pane on `work/t3` both commit; the fixture's `isolate_env` now clears `TLON_LOBBY` so no test inherits it. The spawn test pins the root/child split.
4. **Brief line** sits in `@chat_etiquette`, inside the "WOKEN ON THE LOBBY about a thread you LEAD" paragraph, so it reads in scope for a lead and as noise-free as the rest of that block for everyone else.
5. **Comments carry a why, no devlog.** Hook comment says what the lobby's branch is and why it is fenced; `lobby_export` says what reads it.

## bench_contrast

- `builder-junior: main 2/2 · branch 0/2 · turns 20/14 · REGRESSION`. I read this as a flake, not a signal: on thread 413 (2026-10-28, message 16391) the same canary scored main 0/2 · branch 1/2 with no related change, so it flips on main alone at n=2. The only steering this branch touches is one sentence in the lobby-wake paragraph of the shared etiquette block, which a builder in its own worktree never acts on. No habit proposed.
- `builder-senior: error — a side ran no tasks` recurs identically on 413; it is ticket #623 (builder-senior runs zero tasks), not this branch.
- librarian 2/2 both sides: not a finding.

## Not in scope, noted for the record

A lobby lead that cannot write into `.worktrees/<slug>` from its sandbox will now be stopped at the hook instead of stranding commits on `work/t1`. That is the intended outcome of this ticket; whether a lobby seat should reach the workline worktree at all is #566's family and the tech lead held it after this.
