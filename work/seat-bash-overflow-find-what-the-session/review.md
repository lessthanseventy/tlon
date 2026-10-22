# Review — seat-bash-overflow-find-what-the-session (#329), round 2

Reviewed below the builder's grade: no free reviewer at greybeard was available, so tzinacan (a lower grade) read this round.

**Verdict: approve.** Both findings from round 1 (lonnrot, 1f3775c) are fixed and verified. No new code findings.

## Round 1 findings — fixed

1. **BLOCKING (dirty-tree verify): fixed in 2af5349.** The two `await until("home", () => !screen().includes("THE CAST"))` lines after `keys("C-]")` in `office/test/cast-view.test.ts` are now committed, not left uncommitted on the verify tree. `git status` is empty at HEAD 2af5349; the verify artifact check passed exit 0 on this sha. The fix is coherent: every test that closes the cast with C-] now awaits home before yielding, so the next test's keystrokes can't land on a stale cast. Builder reports 8× parallel runs of cast-view.test.ts → 8/8 pass; verify 804 pass, 0 fail.

2. **Follow-up (multi-line arg grouped as a mount): fixed in cb432f3.** `gawk -v RS='\0'` reads `/proc/1/cmdline` (or the fixture) as NUL-delimited records directly, with no `tr \0 \n`, so a command-string arg containing a line like `--ro-bind` stays one record and can't reset `opt`. The new test case (total 8, and `! grep '/z/'`) goes red on the old script and green on the new. On my own live argv the new script prints the same `total 802` and the same mount groups as before. `gawk` (not `awk`) is the right call here: NUL as RS is a gawk extension, and gawk is what this box and the Nix-managed hosts provide.

## Scope (design, not code — for the tech lead @tertius)

The goal reads "find what the session adds … then bound it". This branch ships the instrument (`scripts/bwrap-argc.sh`) and a flake fix; the overflow itself is still unbounded. #522 is promoted to #320 and held on the operator's host-side `--debug` capture (#11581). @tertius is engaged on the thread and consciously holding; not a code block.

## Follow-ups (non-blocking, still open)

1. #522/#320 remains unbounded. After the host-side capture (#11581) confirms which tree gets scanned, do the bound: refuse a seat launch whose cwd is outside its worktree, and/or sweep the `server/tmp` repos (#558). Tracked as #522; re-listed here so it stays held against this merge.