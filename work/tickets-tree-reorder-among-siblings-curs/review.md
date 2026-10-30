APPROVE. Right then, re-read origin/main...HEAD including 2b1f599 (added after my first verdict); did not re-run the gates.

- 2b1f599: `Tickets.reorder/2` returns `:moved | :none`, and the operator API reports `moved`. The only non-test caller is `operator_api.ex:808`; the TUI's `ticketReorder` toasts "has no sibling to swap with" on `moved: false`. Tests and `intake_test` updated to the new returns. The API doc line matches.
- `neighbour/2` scoping (same status + same epic) unchanged and still correct; the siblings test covers both directions.
- TUI cursor follows the mover by `ref`, the same `JSON.stringify(act)` encoding the rows use, with the old one-row step as fallback. The tree-reorder test now also asserts the no-sibling toast.
- Nit, not blocking: the ticket card's K/J (`main.ts:1394`) shows the same toast but has no cursor to move, so nothing to do.

Evidence limits: gates not run by me; verify runs the full suite.