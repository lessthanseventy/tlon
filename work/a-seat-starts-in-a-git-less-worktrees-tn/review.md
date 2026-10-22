# REQUEST CHANGES — a-seat-starts-in-a-git-less-worktrees-tn

Verdict: **request_changes**. The #563 fix is correct and I approve that part; the branch is missing the second half of the #562 cast-view fix the tech lead required it carry.

Read against the merge-base (a3da37f → HEAD), not origin/main..HEAD: main moved to 0a5b7db with unrelated work (search/ticket/initiatives), so that diff is misleading.

## Blocking

**#562 is half-done — the trailing `C-]` race is still in the branch.** scharlach (#11803) told the builder the branch "should carry the whole #562 fix, not drop half of it," and to add — as its own commit — `await until("home", () => !screen().includes("THE CAST"))` after the trailing `keys("C-]")` at `office/test/cast-view.test.ts:89`. The builder agreed (#11805), then advanced to review at 01:23:49 without adding it: the diff carries only aef3025 (the `until()` double-read), not this line.

Why it matters: aef3025 fixes one cause of the cast-view flake (the double pane read in `until()`). The trailing `C-]` at :89 is the second cause — it is sent and never awaited, so the cast can still be open when the next test ("⏎ on voice is the persona picker", :92) sends its opening `` ` ``. That is the race that red'd verify on the persona-picker test at 00:51:49. The 01:23:49 verify went green, but a green run does not prove a flake is gone — scharlach said "red or green, put that line in." Add the one line (the same wait :83 already does) as its own #562 commit and re-advance.

## The #563 fix (a6bb510) — sound, approved

Traced the error path end to end: `Worktree.add` returns `{:error, {:not_a_checkout, wt}}` when the dir exists with no `.git`; `do_ensure`'s `with` propagates it unchanged; `worktree_for_thread` propagates it; `cwd_export` re-tags it `{:error, refused}`; `mint_and_export`'s `with` short-circuits before minting, so `Spawn.join/env` refuse with `{:error, {:not_a_checkout, wt}}`. `cwd_export` has exactly one caller now (the old call in `exports/3` was removed), so the return-type change is safe. The red-green test is right and its stray dir is cleaned by `with_project`'s `on_exit` `rm_rf!`.

## Follow-ups (non-blocking)

1. **Refusal leaks a staffed thread.** `mint_and_export` runs `ensure` (opens the thread, registers/assigns the agent) before `cwd_export` refuses. So a `not_a_checkout` refusal leaves a staffed thread behind — and for `env`, a freshly-opened one; for `join` with `assign: true`, it can re-assign an existing thread's lead. The fix's core (refuse instead of silently mis-seating) is right; the leak is a separate cleanup concern.
2. **Other `Worktree.ensure` errors still drop `TLON_CWD` silently.** A `not_a_repo` or generic git refusal still makes `cwd_export` return `""` and the pane starts in tmux's default dir — the same fall-up-to-main hazard in another guise. Deliberately scoped out of #563 (learning #3222), but worth a ticket so it isn't lost.