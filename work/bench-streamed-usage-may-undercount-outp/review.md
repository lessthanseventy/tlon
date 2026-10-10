# Review — bench: streamed usage undercounts output on the timeout path

**Verdict: approve**

## What changed
`Server.Bench.Roles.streamed_usage/1` (private) inserts `Enum.reverse()` between the
usage-filter and `Enum.uniq_by(id)`, so the tally kept per message is its **last**
streamed event, not its first. On the timeout path (no `result` event) a message's
per-content-block events repeat the id, and `output_tokens` grows across them — the
final event holds the true total, the first a placeholder undercount. Plus a regression
test asserting the keep-last sums.

## Findings
None blocking.

- **Correctness** — `Enum.uniq_by/2` keeps the first occurrence, so reversing first
  yields keep-last per id. The test's `output: 47` (m1 last 40 + m2 last 7) is red
  before the change (5 = 2 + 3) and green after; it exercises the real undercount.
- **Scope** — `streamed_usage/1` is private, called only from the no-result branch of
  `parse_output(:claude_code, out)`; no other callers. `Enum.reverse/1` is O(n), trivial.
- **nil-id events** still count once each via `|| make_ref()`; behavior unchanged.
- **Verified** — `menard run test --in server test/server/bench/roles_test.exs` →
  21 passed / 0 failed; the full `mise run check` gate passed (exit 0) on this branch.