# Review: #684 office ticket board counts open tickets per node, with an orphans group

**Verdict: approve.** Branch `work/684-office-ticket-board-counts-open-tick` at 820e739, seven commits on top of origin/main. Second round; the first (2dab5ed) approved and QA sent it back.

## What changed since 2dab5ed

One commit, 820e739, two files outside `work/`:

1. `office/tui/data.ts` — `status()` builds the snapshot from a field whitelist, and the whitelist omitted `ticket_open`. Added `ticket_open: j.ticket_open` (absent stays absent, so `viewOf`'s `undefined` path from 9ee2df3 still holds).
2. `office/test/data.test.ts` — the fake `/office` now sends `ticket_open: { "1": { total: 3, loose: 1 } }` and the status test asserts it arrives.

That is the whole cause of QA's `orphans · 0 open` / `TICKETS · 2` on the smoke: the server sent `loose 1, total 3`, the client dropped the field and fell back to the row count and a zero sum. The fix is the minimum, and the test would have been red before it. No server change this round, so my round-one findings on `Room.open_counts/2`, `bump_up`, and the payload stand as verified.

## Verified

- `git diff 2dab5ed..820e739 -- . ':!work/684-…'` is the two hunks above and nothing else.
- CHECKS: `mise run check` green at 21:41 (office 926 pass, 0 fail; server suite green). No `bench_contrast` row, so nothing to call a regression or a flake.
- The builder filed the sibling bug she found (`ticket_week` dropped by the same whitelist) as #688 rather than widening the change. Right call.

## Not verified

The live-db screenshot the ticket asks for (kids 585 → Toy 588; engine 587 → six epics). QA drove a scratch smoke with the `ticket_tree` fixture, not the live db; the live drive is owed after the cut that carries this.

## Non-blocking, as follow-ups

See the follow_ups list: the live drive; the orphans header's no-`ticket_open` fallback (round one, still open, moot post-cut); `Room.board/1` `@doc`/`@spec` still naming only `epics`/`loose` (round one, still open, second time asked); the orphans header and column total counting started loose tickets the rows hide; a depth cap on `bump_up`.
