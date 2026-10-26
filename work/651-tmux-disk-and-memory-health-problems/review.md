APPROVE — #651 health needs. Read the diff (needs.ex, room.ex, tlon-cli job verb, TUI kind/tone, profiles brief); I did not run the suite myself.

Right then. Checked:
- `health/0` yields keyed `health:tmux|disk|mem` items, level decide, each gone when its predicate is false. `vital_problems/1` is shared with `problems/1`, so the two views can't drift.
- Wired consistently: `@clipboard`, `pass_up_rule` (narrow), the moduledoc routing table, TUI `NEED_KIND`/`NEED_TONE` and the `Need` kind union.
- `tlon-cli job`: verb limited to retry|dismiss and id to digits before interpolation, so no injection. `retry_job/1` and `dismiss_job/1` exist in Needs.
- Test config stubs the reading, so tests don't depend on `df` or tmux.

Nits (non-blocking, filed as follow-ups):
1. server/config/test.exs: the `release_root` line moved below the "stale-launch sweep" comment, which now sits over the wrong config line.
2. `Room.vitals/0` re-puts a `:persistent_term` every minute, which triggers a global GC scan; ETS or an Agent is the usual home.
3. `at: DateTime.utc_now()` re-stamps on each poll, so health items always sort newest. Same shape as the other computed items.