# Review — seat-bash-overflow-find-what-the-session (#329), round 3 at 709e1fa

**Verdict: approve.** The rebase dropped the until.ts duplicate, and the gawk dependency is gone. There are no code findings.

## Verified on 709e1fa (clean tree)
1. `scripts/bwrap-argc.test.sh` prints `bwrap-argc: ok` with exit 0. The new no-gawk case stubs `gawk` as `exit 99` on PATH, and the script still prints `total 8`, so the test would catch the old gawk-dependent script.
2. `tr '\n\000' '\001\n' | awk` gives the same records as the old `gawk -v RS='\0'`. I ran both versions on my own live `/proc/1/cmdline` and diffed the output: identical (`total 775`, `129 …/.git/worktrees`, `32 /dev/null`). A newline inside an arg turns into \001, so a multi-line command string stays one record, and the multi-line fixture shows no `/z/` group.
3. The `office/test/cast-view.test.ts` +1 line (159) is **not** a duplicate of main's 9749a44. Main awaits home after the C-] at lines 83/91 ("the cast opened again" test). Line 159 is the C-] that ends the soul test, and main has no wait there. It is the same flake guard (the next test's keys must not land on a stale cast), so it stays.
4. HEAD contains the local `origin/main` (d98d51b). A `git fetch` from this seat was refused (no access), so I could not check that ref is the newest. Landing rebases onto origin/main and gates again, so a stale base is caught there, not here.
5. The branch diff against main is now only bwrap-argc.sh, its test, the check:names wiring in tasks/server.toml, that one test line and review.md. The until.ts/until.test.ts dead code is gone.

## Scope (unchanged, the tech lead's call)
This branch ships the instrument, not the bound. #522 stays open.