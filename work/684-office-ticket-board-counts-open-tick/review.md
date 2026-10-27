# Review: #684 office ticket board counts open tickets per node, with an orphans group

**Verdict: approve.** Branch `work/684-office-ticket-board-counts-open-tick` at 3e4f7d6, six commits on top of origin/main. The ask's three points are met by the diff, and nothing in it is a bug.

## What I verified

1. **The counts are the server's, recursive, open-only.** `Room.open_counts/2` rejects `status == "done"` (the only terminal status: `Ticket.@statuses ~w(backlog todo doing done)`), then `bump_up` walks `parent_of` to the root, so one open leaf counts once under its epic and once under its initiative. A ticket linked straight under an initiative and a started loose ticket are both counted (`room_test`: Toy 1, Kids 2, loose 2, total 4). `open_in_workspace` rows carry `open` for epics and initiatives via the merged `boards` in `add_progress/2`; `ticket_open[ws] = {total, loose}` rides the payload (`office_test`).
2. **No client-side `.length` in any shown number.** `groupTitle` and `stickyItems` read `tk.open`; the column title reads `openTotal(a, …)` for col 0; the orphans header reads `openOf(a)`. The only remaining `.length` fallbacks fire when the server sent no `ticket_open` at all (`viewOf` keeps it `undefined`, not `{}`, since 9ee2df3).
3. **Orphans group.** `treeRows` walks groups first, then pushes one `header` row with `act {column,0}` and the loose leaves at depth 1, always last regardless of the level order (test "the order applies to each level on its own"). `main.ts` skips the `#id` key, makes Enter a no-op and withholds `column.space` on it. No crash path.
4. **`bump_up` cannot loop.** `TicketLink.pairing/3` only admits initiative→epic→ticket, and an initiative can't have a parent, so a chain is at most two links.
5. **Measured:** `scripts/cap.sh bun test office/test/board.test.ts` → 28 tests, 0 fail, exit 0 (recorded). CHECKS: `mise run check` green on the branch (train with #399, #397). No `bench_contrast` row.

## Not verified

The live-db screenshot (kids 585 → Toy 588; engine 587 → six epics) the ticket asks for. pr.md says why: the running service predates `Room.board`'s new keys, so a drive against :4040 would show the old numbers. That is true and not the builder's to fix; it is owed after the release that carries this change, see follow-ups.

## Non-blocking, as follow-ups

See the follow_ups list: the live drive owed after release; the orphans header's missing pre-restart fallback; `Room.board/1`'s `@doc`/`@spec` not naming the new keys.
