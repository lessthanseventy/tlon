APPROVE — the blocking bug from the prior review (runeberg, 883de44) is fixed; nothing new blocks.

Reviewer model: claude-fable-5-1, a different model than the builder's (claude-sonnet-5-5 on a1fe73f).

Verified: `bun test test/scharlach.test.ts test/seat-voices.test.ts` → 14 pass, 0 fail; `bunx tsc --noEmit -p office` clean. Did not drive the TUI. Traced `tickLedger` (`office/tui/main.ts`) by hand: on a green board (`all.triage[sws]` 0) it now falls through to `tickFromTriage(ledger, 0, [], threads)` → `ticked` becomes an empty Set, demerits kept, so a re-red ticks again. The new unit test covers exactly that seam.

## Changed since 883de44
- `tickFromTriage` added in `kit/scharlach.ts`; `tickLedger` only returns early when the fetch of a non-green triage fails (correct: an unknown board should not clear memory).
- Test "a fully green board (triage count 0) clears the ticked memory" added.

## Non-blocking (follow_ups)
- Double tick in one pass: `failed_checks` is uniq by {thread, cmd}, so a thread with two distinct failed check cmds appears twice in `shown`; `tickForRedThreads` checks the OLD ledger's `ticked`, so both tick in the same refresh. Dedupe `redIds` or check the in-progress `ticked`.
- `failed_checks.shown` is capped at 5 (`Server.Office.Room` `@cap`). With more than 5 reds, threads outside the cap aren't in `redIds`, get dropped from `ticked`, and re-tick if they rotate back in. Presentation only.
- Scharlach's canned "The build is red. I have recorded the demerit." fires at a game/couch regardless of build state.
- `seatLine`'s `{name}` → "you" replacement is dead (no line uses it).
- Fallback fires whenever `data.talk` returns `[]`, including server-side throttling, not only `--sandbox`; the comment overstates.
- Missing trailing newline in `kit/scharlach.ts` and `kit/seat-voices.ts`.