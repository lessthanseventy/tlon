Closes #639 (from the review of #616).

**What changed**

- **Reorder moves among siblings.** `Tickets.reorder/2` now finds its neighbour among tickets in the same status column *and* the same epic (a top-level ticket's siblings are the other top-level tickets). Before, a child could trade places with a loose ticket or another epic's child. No migration: this is a query change.
- **The cursor follows the moved ticket.** After K/J resolves, the TUI puts the cursor on the row whose `ref` is the moved ticket. It falls back to the old one-row step only when no row matches.
- **The dead rail ticket tip is gone.** Tickets only sit in the TICKETS column, which the rail draws from its stickies, so the ticket branch of the rail's per-item sticky map was never reached. `Focus.armed`, which only that branch read, is removed with it.

**How it was checked**

- Server: a new `Tickets.reorder` test that a child under epic A never trades with a loose ticket or another epic's child. It failed on the old code and passes now. `tickets_test.exs`: 36 tests, 0 failures.
- TUI: `office/test/tree-reorder.test.ts` drives the real TUI. K on a ticket with an open epic beside it leaves the cursor on the moved ticket. It failed on the old code and passes now.
- `mise run office:check`: 962 tests across 138 files, 0 failures, exit 0.
- Server gate: `menard run check --in server` (see the thread for its result).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
