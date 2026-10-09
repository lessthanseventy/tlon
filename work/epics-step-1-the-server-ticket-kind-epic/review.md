APPROVE — no free reviewer is at the builder's grade (greybeard); tzinacan (reviewer grade) leads this review.

Verified by reading the diff (origin/main...HEAD) only. I did not run the suite; the recorded `mise run check` exit 0 on the rebased head is the test evidence.

**Spec fit**
- Migration `20261009000000_ticket_kind` is a single reversible ALTER with a CHECK and a default, so existing rows stay `ticket`.
- The parent law (epic-only parent, no epic child, one parent) is enforced in the `TicketLink` changeset.
- `route/1` and `start_thread/2` refuse an epic with `{:error, :epic}`, and `Intake.next` filters `kind == "ticket"`.
- Epic status is derived and stored. Every child write path I found (`update`, `promote`, `remove`, `link`/`unlink` of `parent`) calls `refresh_epic`. `done_for`, `undone_for` and the sweep all go through `update`, so they are covered.
- `refresh_epic` writes the epic directly, so it cannot recurse.

**Non-blocking findings**
1. The parent-law checks and the ticket lookups are not in a transaction. Two concurrent parent links to the same child can both pass `one_parent`. The DB has no partial unique index on `(to_id) WHERE kind='parent'`. Suggested follow-up: add that index.
2. An epic's `status` is still castable through `update_changeset` (`@mutable` includes it), so a caller can set it by hand. It is overwritten at the next child write. Suggested follow-up: drop `:status` from the cast when `kind == "epic"`.
3. "Step order" in `first_step_of_each_epic` picks the lowest-sort *eligible* backlog child. If step 1 is `doing`/`todo` or blocked, step 2 becomes eligible and can run in parallel. Fine if parallel steps are intended; if not, order with `blocks` links.
4. There is no MCP or API surface to set `kind` yet. I assume that belongs to a later step.

None of these blocks the merge.