# APPROVE — a-seat-starts-in-a-git-less-worktrees-tn

Verdict: **approve**. The blocking gap from my first review is fixed and verify is green.

## What changed since the last review (6584456 → ae862ad)

One commit, one line — exactly the fix I required. `ae862ad` adds `await until("home", () => !screen().includes("THE CAST"))` after the trailing `keys("C-]")` at `office/test/cast-view.test.ts:90`. It mirrors the wait at :83 after the earlier `C-]`, so the cast is closed and the screen settled before the next test ("⏎ on voice is the persona picker", :93) sends its opening `` ` ``. That trailing-unawaited-`C-]` was the second cause of the cast-view flake (the one that red'd verify on the persona-picker test at 00:51:49); the first cause was aef3025's `until()` double-read, already on the branch. Both halves of #562 ride this line now, as scharlach required. Verify passed on the branch (it came back to review, which is the gate's own green).

## #563 (a6bb510) — sound, unchanged

Re-affirmed on this pass: `Worktree.add` → `{:error, {:not_a_checkout, wt}}` propagates unchanged through `do_ensure`/`worktree_for_thread`, `cwd_export` re-tags it `{:error, refused}`, and `mint_and_export`'s `with` short-circuits before minting — so `Spawn.join/env` refuse loud instead of dropping `TLON_CWD`. `cwd_export` has the one caller; the return-type change is safe. Red-green test is right; stray dir cleaned by `with_project`'s `on_exit rm_rf!`.

## Follow-ups (non-blocking, still open)

Carried from the first review — both already tracked, neither sits in lines this change touches:

1. **Refusal leaks a staffed thread.** `mint_and_export` runs `ensure` (opens thread, registers/assigns agent) before `cwd_export` refuses, so a `not_a_checkout` refusal leaves a staffed thread behind (freshly opened for `env`; re-assigned lead for `join` with `assign: true`). The reorder is out of scope for this change.
2. **Other `Worktree.ensure` errors still drop `TLON_CWD` silently** — `not_a_repo` / generic git refusal still return `""` from `cwd_export`, pane starts in tmux's default dir. Filed as #566.