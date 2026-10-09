VERDICT: approve

Reviewed 11de4ca (intake.ex, intake_test.exs) by reading the diff only. I did not run the suite. The server's verify stage recorded `mise run check` green on this branch.

- Spec: `in_flight/1` now skips a `todo` ticket whose promoted thread is closed, via a correlated `not exists` on TicketThread joined to Thread. The new test matches the ticket's check: a closed-thread todo ticket with cap 1 does not block routing of the next ticket.
- Scope: surgical. The diff is one query and one test.
- Non-blocking, as emma flagged: the sheriff notice was not added. That is defensible, since without dedupe state it would repeat on every cron pass. File it as a follow-up if wanted.
- Non-blocking: a ticket with both a closed and an open promoted thread counts as slot-free. That is correct only if the open thread is counted elsewhere in `all`. Worth confirming, but not a regression, because the old code counted it once either way.
- Nit: `|> from(as: :t)` after the query is built works but is unusual. Putting `as: :t` in the first `from` would read better.