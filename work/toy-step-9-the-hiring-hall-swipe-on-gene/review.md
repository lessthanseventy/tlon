# Review — toy step 9, the hiring hall (thread 257)

**Verdict: request_changes.** The two kit commits (bbe49b3, 2d31bf8) are clean and tested, but the branch is 2 of 7 plan tasks and the build stage's owed artifact is missing. Emma said so herself (#7107); the stage moved on without her. Nothing here is wrong code; it is an unfinished change.

## Blocking

1. **pr.md is not committed.** The build brief owes `work/<slug>/pr.md`; the branch has none.
2. **Spec §9 definition of done is unmet; merging would close #65 with no hall.** No hall view (task 5), no keys, no sandbox hire, no `office:drive` check (§9.3). `kit/hall.ts` has no caller on main, so a merge lands dead code and closes the ticket. Tasks 1/2/6/7 stay blocked on souls-step-2 and are not asked for here; task 5 + pr.md are not blocked and finish the sandbox half.
3. **`Overrides` cannot carry a look edit (spec §2 `e`, §3/§6 "seed plus edits, re-renders identically").** `Overrides = Partial<Pick<Candidate, "name"|…|"drawn">>` has no parts, so an edited accessory is lost on ↑ (pile) and on `hall.json`. Emma's uncommitted test in the worktree ("a part override replaces a slot, null clears it") already names the fix: a `parts?: Partial<Record<Slot, PartSpec | null>>` override applied into `look.parts` (`null` clears the slot). Land it with task 5, since that is where `e` arrives.

## Verified
- Read the full diff (`git show main..HEAD -- office/`): `roll` is pure, seeded, locks carry over, a locked name that is since taken re-rolls, names match Server.Soul's regex, Borges list ≥24 and legal. Commit trailers name the model that wrote them.
- `cd office && bun test test/hall.test.ts`: 15 pass, 1 fail; the failure and the `tsc` error are the uncommitted worktree test above, not the branch.
- Server verify: `mise run check` exit 0 on the branch (brief, 12:39:20Z).

## Non-blocking (follow-ups, filed)
- `loadHall` accepts any object as `locks`; a hand-edited `slots: "head"` or `slots: 3` reaches `roll` and misbehaves or throws. Filter to arrays of known `Slot`/`Field` values.
- `pushPile` does not dedupe by seed: bringing a pile entry back and pressing ↑ again stores it twice.

## Process
The workline advanced build→verify at 12:31:53Z with no `advance_stage` from the builder (emma, #7107); filed as a ticket. Emma's ask #7108 to the operator is still open: this verdict is her option (1). If Andrew answers (2), the next review round approves the kit as it stands and the follow-ups ride.
