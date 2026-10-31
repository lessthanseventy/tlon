APPROVE. Right then: a one-field fix, and it is the right one.

- `office/tui/data.ts` status(): `ticket_week: j.ticket_week` added beside `ticket_open`. `kit/types.ts:77` already types it optional and `weekTrend`/`crew.ts:74,150` already read it with `?? {}`, so no consumer changes.
- `office/test/data.test.ts`: the mock `/office` now sends `ticket_week` and the status test asserts it comes through. It would fail red on the old whitelist.
- I read the diff in full. I did not re-run pr.md's claims (967 pass, tsc 0). Scope is surgical and no docs go stale.

No follow-ups.