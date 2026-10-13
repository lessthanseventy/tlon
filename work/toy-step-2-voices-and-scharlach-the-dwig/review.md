APPROVE — the rebase onto main is clean; nothing new since my 196d41a approval.

Reviewer model: claude-fable-5-1, a different model than the builder's (claude-sonnet-5-5).

## What changed since 196d41a
The branch was rebased onto origin/main after the merge queue hit a conflict in `office/tui/main.ts`. Verified:
- `kit/scharlach.ts`, `kit/seat-voices.ts` and both test files are byte-identical to the previously approved tip (`git diff 196d41a HEAD -- <those files>` is empty).
- The `main.ts` delta before vs after the rebase differs in exactly one line: the `onTogether` fallback now hands `said` to main's new `room().converse(said); heard(said); changed()` instead of the old per-turn `setTimeout` loop. `converse` takes `{who, line}[]` and `heard` dedupes into the said log, so the canned fallback turns flow through the same path as server-written ones. Correct resolution; main's OFFICE_WIDE/step/held changes are kept.
- `office/AGENTS.md` line still describes the shipped behaviour.

Checks: `bun test test/scharlach.test.ts test/seat-voices.test.ts test/banter.test.ts` → 17 pass, 0 fail; `bunx tsc --noEmit -p office` clean. The server's verify stage ran `mise run check` green on this branch (06:22Z). Did not drive the TUI.

## Non-blocking (follow_ups, unchanged from last round)
- Double tick in one pass when a thread has two distinct failed check cmds (`failed_checks` uniq by {thread, cmd}; `tickForRedThreads` reads the old `ticked`).
- `failed_checks.shown` cap of 5: reds outside the cap drop from `ticked` and re-tick when they rotate back in.
- Scharlach's "The build is red. I have recorded the demerit." canned line fires at a game/couch regardless of build state.
- `seatLine`'s `{name}` replacement is dead.
- Fallback fires whenever `data.talk` returns `[]`, including server-side throttling; the comment says `--sandbox`.
- Missing trailing newline in `kit/scharlach.ts` and `kit/seat-voices.ts`.