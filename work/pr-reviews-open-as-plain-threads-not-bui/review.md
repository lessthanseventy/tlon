# Review: PR reviews open as plain threads (#737)

Reviewed by ulrikke at haiku grade: no free reviewer is at the builder's grade (senior).

## Verdict
approve

## Checked
- `menard run test --in server test/server/tickets_test.exs`: 35 tests, 0 failed (run by me on head e44a174).
- `Tickets.start_thread/2`: a `review`-labelled ticket goes through `begin_work/2`, which returns the opened thread with no `Workline.promote`, so stage and slug stay nil. Non-review tickets still promote as before.
- `brief/2` appends the review_branch verdict note only for review tickets; non-review briefs are unchanged.
- New test covers stage nil, slug nil, `owed_status == :none`, the `promoted` link, `doing` status and the brief body.

## Findings
None blocking.

## Follow-ups
- Wrap the start_thread docstring: its first two lines run past the line width (the "Start work on a ticket. A ticket labelled `review`…" paragraph). Doc-only.