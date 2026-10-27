Closes #405: a provider's refusal becomes a `quota` Need.

- `Shifts` `@quota_out` was blind to the lines this box prints ("You've hit your session / weekly /
  monthly spend limit"); fixed on its own, first commit.
- `Shifts.provider_limit/1` reads Claude Code's `API Error: Request rejected (NNN)` wrapper. A 429
  naming a "usage limit" (ollama's spent plan) is a quota item at once, no debounce; any other
  status is `Logger.info`ed with its raw line, so the first real 402 writes its own fixture.
- Pane door: `Shifts.quota_check/4` now reads non-Claude seats too. One-shot door: `ModelCli` hands a
  failing call's stderr to `Shifts.refused/2` (30-minute entry, per workspace seating that provider).
- `Needs.quota/0`: a third source, keyed `quota:<ws>:<provider>` like the balance poll's "spent" item,
  so the operator sees one item; the refusal's raw line is its text (the reset/upgrade hint).
- `reset_at/2` also reads "resets Sep 28, 9am".

Fixtures are verbatim pane lines from this box's `~/.claude/projects` transcripts. No 402 has been
captured: nothing here matches or fabricates one.

Checked: `menard run check` in server, 2239 tests, 0 failures.
